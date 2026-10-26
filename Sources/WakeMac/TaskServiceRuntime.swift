// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import Darwin
import WakeMacCore

/// Same engine as the application, separate process and lifetime, no windows.
@MainActor final class TaskServiceRuntime {
    var model: AppModel!
    private var server: LocalControlServer?
    private var timer: Timer?
    private var ready = false
    private var ticking = false
    private var notifier: LocalNotifier?
    private var lastRefresh = Date.distantPast
    private let root = TaskServiceLauncher.stateDirectory
    func start() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Tests and explicit alternate instances use separate preferences as well as files.
            let defaults = TaskServiceLauncher.isolatedPreferences ?? .standard
            model = AppModel(backend: MacBackend(preferences: defaults, allowsAuthentication: false), preferences: defaults,
                             historyURL: root.appendingPathComponent("history.json"), jobLogDirectory: root.appendingPathComponent("Task Logs"))
            model.isTaskService = true
            if Bundle.main.bundleIdentifier != nil {
                let notifier = LocalNotifier(preferences: defaults)
                notifier.configure(); self.notifier = notifier
                model.notices.onArrival = { [weak notifier] notice, external in
                    if external { Task { await notifier?.sendNotice(notice) } }
                }
                model.notificationHandler = { [weak model] text in
                    model?.notices.post(.activity, title: "工作提醒", body: text)
                }
                model.thermalNotificationHandler = { [weak model] text, _ in
                    model?.notices.post(.thermal, title: "温度保护触发", body: text)
                }
                model.featureNotificationHandler = { [weak model, weak notifier] text, event in
                    model?.notices.post(.activity, title: "工作会话", body: text, systemNotification: false)
                    notifier?.send(text, event: event)
                }
            }
            model.serviceInfo = TaskServiceInfo(stateDirectory: root.path)
            model.stopTaskService = { [weak self] in self?.shutdown() }
            model.finalBatteryReading = { BatterySource.read() }
            server = try LocalControlServer(path: TaskServiceLauncher.socketPath) { [weak self] request in
                guard let self else { return ControlReply(ok: false, error: "Service is stopping") }
                return await self.reply(request)
            }
            // Only the endpoint owner may recover history or change power.
            model.recoverWorkRequests(from: root.appendingPathComponent("work-requests.json"))
            try model.recoverPlans(from: root.appendingPathComponent("execution-plans.json"))
            Task {
                await model.choose(.normal, automatic: true, startupRecovery: true)
                ready = true
                log("Task service ready; pid=\(getpid())")
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.ticking else { return }
                        self.ticking = true
                        defer { self.ticking = false }
                        self.model.reloadServicePreferences()
                        if Date().timeIntervalSince(self.lastRefresh) >= 10 {
                            self.lastRefresh = Date(); await self.model.refresh()
                        }
                        if let deadline = self.model.pendingUnlockedDeadline,
                           Date() >= deadline || self.model.pendingUnlockedOwner?.isAlive != true {
                            self.model.pendingUnlockedDeadline = nil; self.model.pendingUnlockedOwner = nil
                            await self.model.choose(.normal, automatic: true)
                        }
                        await self.model.tick(battery: BatterySource.read())
                        await self.model.advancePlans()
                    }
                }
            }
        } catch { log(error.localizedDescription); exit(1) }
    }
    private func reply(_ request: ControlMessage) async -> ControlReply {
        guard ready else {
            var reply = ControlReply(ok: false, error: "Task service is starting"); reply.service = model?.serviceInfo; return reply
        }
        return await model.handleTaskControl(request)
    }
    private func log(_ message: String) {
        let path = root.appendingPathComponent("task-service.log")
        if !FileManager.default.fileExists(atPath: path.path) { FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let file = try? FileHandle(forWritingTo: path) {
            defer { try? file.close() }; _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data((Date().ISO8601Format() + " " + message + "\n").utf8))
        }
    }
    private func shutdown() { timer?.invalidate(); server?.stop(); exit(0) }
}

extension AppModel {
    func reloadServicePreferences() {
        reloadWorkPolicyPreferences(); profiles.reload(); triggers.reload()
        thermalThreshold = ThermalThreshold(rawValue: preferences.string(forKey: "orexin.thermal.threshold") ?? "") ?? .critical
        thermalReleaseEnabled = preferences.object(forKey: "orexin.thermal.releaseEnabled") as? Bool ?? true
        automation.batteryEnabled = preferences.object(forKey: "orexin.BatteryProtection") as? Bool ?? true
        automation.batteryThreshold = min(50, max(5, preferences.object(forKey: "orexin.BatteryThreshold") as? Int ?? 20))
    }
    func handleServiceControl(_ request: ControlMessage) async throws -> ControlReply? {
        switch request.operation {
        case "service-status":
            guard isTaskService else { throw ModeError("This is a legacy GUI endpoint; quit it and start the background service") }
            return taskControlReply()
        case "service-stop":
            guard isTaskService, workRequests.active.isEmpty, runningCommandIDs.isEmpty,
                  !planRuns.contains(where: { !$0.state.terminal }), !busy else { throw ModeError("Service still owns active work; finish or stop it before shutting down") }
            serviceStopping = true
            var committed = false
            defer { if !committed { serviceStopping = false } }
            await choose(.normal, automatic: true)
            guard workRequests.active.isEmpty, runningCommandIDs.isEmpty, !planRuns.contains(where: { !$0.state.terminal }),
                  !error, active == .normal else { throw ModeError("Power cleanup was not verified; service is still running") }
            let reply = taskControlReply(); committed = true
            Task { try? await Task.sleep(for: .milliseconds(150)); self.stopTaskService?() }
            return reply
        case "plan-validate":
            guard let data = request.document else { throw ModeError("Plan JSON required") }
            let plan = try ControlCoding.decode(ExecutionPlan.self, from: data).validated()
            var reply = taskControlReply(); reply.document = try ControlCoding.encode(plan); return reply
        case "plan-run":
            guard let data = request.document, data.count <= 32 * 1024, let id = request.id else { throw ModeError("Plan JSON (at most 32 KiB) and run ID required") }
            let run = try await startPlan(ControlCoding.decode(ExecutionPlan.self, from: data), id: id)
            var reply = taskControlReply(); reply.document = try ControlCoding.encode(run); return reply
        case "plan-list": return taskControlReply()
        case "plan-status", "plan-cancel":
            guard let id = request.id else { throw ModeError("Plan ID required") }
            if request.operation == "plan-cancel" { try await cancelPlan(id: id) }
            guard let run = planRuns.first(where: { $0.id == id }) else { throw ModeError("Unknown plan") }
            var reply = taskControlReply(); reply.document = try ControlCoding.encode(run); return reply
        case "release-user":
            guard let id = request.id else { throw ModeError("Request ID required") }
            if planRuns.contains(where: { $0.id == id }) { try await cancelPlan(id: id) }
            await releaseWork(id: id); return taskControlReply()
        case "command-start":
            guard let command = request.command, command.utf8.count <= 16 * 1024, let directory = request.directory else { throw ModeError("Command and directory required") }
            // Submission is acknowledged only after a verified request exists.
            let plan = ExecutionPlan(title: request.spec?.title ?? "Command", tasks: [.init(id: "command", command: command, directory: directory)],
                                     mode: request.spec?.mode ?? .desk, screen: request.spec?.screen ?? .idle, teardown: request.spec?.teardown ?? .restore)
            let run = try await startPlan(plan, id: request.id ?? UUID(), requestSpec: request.spec)
            var reply = taskControlReply(); reply.document = try ControlCoding.encode(run); return reply
        case "cancel-battery-sleep":
            automaticSleepRevision += 1; automation.cancelBatterySleep()
            return taskControlReply()
        case "cancel-sleep": cancelAutomaticSleep(); return taskControlReply()
        case "interface-settings":
            if let enabled = request.enabled { await setRequireImmediateLock(enabled) }
            return taskControlReply()
        case "unlocked-setting":
            guard let enabled = request.enabled else { throw ModeError("Unlocked-work setting required") }
            await setUnlockedWork(enabled); return taskControlReply()
        case "unlocked-ready":
            guard let deadline = pendingUnlockedDeadline, Date() < deadline, pendingUnlockedOwner?.isAlive == true,
                  let backend = backend as? MacBackend else { throw ModeError("Authorization lease expired; start again") }
            try await backend.renewPendingUnlockedWork()
            pendingUnlockedDeadline = Date().addingTimeInterval(30)
            return taskControlReply()
        case "unlocked-prepare":
            guard let backend = backend as? MacBackend else { throw ModeError("Native backend required") }
            guard let owner = request.owner, owner.isAlive == true, workRequests.active.isEmpty else { throw ModeError("An active interface owner and no active work are required for authorization") }
            await setUnlockedWork(true)
            try await backend.prepareUnlockedWorkFromInterface()
            pendingUnlockedOwner = owner; pendingUnlockedDeadline = Date().addingTimeInterval(120)
            return taskControlReply()
        case "unlocked-finish":
            guard let backend = backend as? MacBackend else { throw ModeError("Native backend required") }
            try await backend.verifyUnlockedWorkFromInterface()
            return taskControlReply()
        case "display-sleep":
            await sleepDisplayNow()
            return taskControlReply()
        case "sleep-now":
            await choose(.normal, sleep: true)
            var reply = taskControlReply(); if error || pending != nil { reply.ok = false; reply.error = message }; return reply
        default: return nil
        }
    }
}
