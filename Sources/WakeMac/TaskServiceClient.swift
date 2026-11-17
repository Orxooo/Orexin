// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import WakeMacCore

actor ServiceModeBackend: ModeBackend {
    let path: String
    init(path: String) { self.path = path }
    func snapshot() async throws -> Snapshot {
        let path = path
        let reply = try await Task.detached { try LocalControlSocket.call(.init("status"), path: path) }.value
        guard reply.ok, let snapshot = reply.snapshot else { throw ModeError(reply.error ?? "Background service state unavailable") }
        return snapshot
    }
    func configurePower(_ mode: WorkMode) async throws { throw ModeError("Power changes must go through the task service") }
    func requestLockPolicy(_ policy: LockPolicy) async {
        await MainActor.run { if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") { NSWorkspace.shared.open(url) } }
    }
    func sleepNow() async throws {
        let path = path
        let reply = try await Task.detached { try LocalControlSocket.call(.init("sleep-now"), path: path) }.value
        guard reply.ok else { throw ModeError(reply.error ?? "Sleep was not verified") }
    }
}

private struct TaskServiceConnectionFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

extension AppModel {
    func serviceCall(_ message: ControlMessage) async throws -> ControlReply {
        guard let path = serviceSocket else { throw ModeError("No background service endpoint configured") }
        let reply: ControlReply
        do { reply = try await Task.detached { try LocalControlSocket.call(message, path: path) }.value }
        catch { throw TaskServiceConnectionFailure(reason: error.localizedDescription) }
        guard reply.ok else { throw ModeError(reply.error ?? "Background service request failed") }
        guard reply.service?.protocolVersion == 1 else { throw ModeError("Quit the older Orexin application and start the current task service") }
        return reply
    }
    func adoptServiceReply(_ reply: ControlReply) {
        if reply.displayDimmingPaused == true, !busy, triggerOwnedMode == nil, interfaceHandle != nil, interfaceSpec?.screen == .dim,
           let mode = reply.mode, mode != .normal, workScreen.ownBehavior(for: mode) == .dim {
            workScreen.select(.normalBrightness, for: mode)
        }
        workScreen.observeServiceDimState(paused: reply.displayDimmingPaused, needsAccess: reply.dimExitNeedsInputAccess)
        if let service = reply.service {
            if let previous = connectedServiceInstanceID, previous != service.instanceID {
                interfaceHandle = nil; interfaceSpec = nil
            }
            connectedServiceInstanceID = service.instanceID
            serviceInfo = service
            coreUpgradeRequired = reply.capabilities?.contains("independent-core-v1") != true
            sessions.screenSaverControlAvailable = reply.capabilities?.contains("session-effects-v1") == true
            let supported = reply.capabilities?.contains("notices-v1") == true
            if !supported {
                notices.post(.serviceUpgradeRequired, title: "后台提醒尚未完整启用",
                             body: "旧后台服务仍在运行，暂不支持新的消息提醒。请完成当前任务，再退出并重新启动后台服务；现有任务不会被强行中断。",
                             id: "service-upgrade.\(service.instanceID)")
            } else if serviceNoticeSupport == false {
                notices.post(.serviceRecovery, title: "后台事件提醒已启用", body: "已连接支持消息提醒的后台服务。")
            }
            serviceNoticeSupport = supported
        }
        if let data = reply.coreRuntime, let core = try? ControlCoding.decode(CoreRuntimeSnapshot.self, from: data) {
            if let statistics = core.statistics { behavior.observeStatistics(statistics) }
            workScreen.reloadConfiguration()
            workScreen.runtimeBehavior = core.screenBehavior
            sessions.observeRuntime(core.session)
            manualWorkMode = core.manualMode; sessionWorkMode = core.sessionMode
            triggerOwnedMode = core.triggerMode; triggerOwnedRuleID = core.triggerRuleID
            triggerSummary = core.triggerSummary; automation.deadline = core.timer
        }
        profiles.reload(); triggers.reload()
        workRequests = WorkRequestLedger(observing: reply.tasks.map(\.request))
        remoteTaskStatus = Dictionary(uniqueKeysWithValues: reply.tasks.map { ($0.request.id, $0) })
        runningCommandIDs = Set(reply.tasks.filter(\.commandRunning).map { $0.request.id })
        commandLogs = reply.commandLogs?.mapValues { URL(fileURLWithPath: $0) } ?? [:]
        jobRunning = !runningCommandIDs.isEmpty; servicePlans = reply.plans ?? []
        snapshot = reply.snapshot; active = reply.mode; serviceSleepAt = reply.sleepAt
        if let data = reply.notices, let remote = try? ControlCoding.decode([ClientNotice].self, from: data) {
            notices.ingest(remote)
        }
        automation.observeServiceCountdowns(battery: reply.batterySleepAt, job: reply.sleepAt)
        if let data = reply.timeline, let events = try? ControlCoding.decode([HistoryEntry].self, from: data) {
            history = Array((events + historyStore.entries).sorted { $0.date > $1.date }.prefix(200))
        }
        if let service = reply.service { requestServiceMessage = LF("后台服务运行中 · PID %d", service.pid) }
        onUpdate?()
    }
    func connectTaskService() async {
        corePaused = false
        serviceRecoveryEnabled = true
        do {
            let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            let socket = serviceSocket ?? TaskServiceLauncher.socketPath
            let reply = try await launchTaskService(executable, socket)
            adoptServiceReply(reply)
            error = coreUpgradeRequired
            message = coreUpgradeRequired ? "后台核心版本较旧；结束当前工作后，请在核心与授权中重新启动核心。" : "已连接后台任务服务。"
        } catch {
            self.error = true; message = error.localizedDescription; requestServiceMessage = message
            reportPowerServiceFailure(message)
        }
    }
    func refreshTaskService(renew: Bool = false) async {
        guard !corePaused, !serviceRefreshRunning else { return }
        serviceRefreshRunning = true
        defer { serviceRefreshRunning = false }
        let stopEpoch = workStopEpoch, previousInstance = connectedServiceInstanceID, observedGeneration = generation
        do {
            let reply: ControlReply
            do { reply = try await serviceCall(.init("status")) }
            catch is TaskServiceConnectionFailure {
                guard serviceRecoveryEnabled, Date() >= serviceRetryAt else {
                    throw ModeError("后台服务暂时不可用，正在自动重连。")
                }
                serviceRetryAt = Date().addingTimeInterval(serviceRetryDelay)
                serviceRetryDelay = min(serviceRetryDelay * 2, 30)
                let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
                reply = try await launchTaskService(executable, serviceSocket ?? TaskServiceLauncher.socketPath)
            }
            guard generation == observedGeneration, workStopEpoch == stopEpoch else { return }
            adoptServiceReply(reply)
            if serviceConnectionFailed { serviceConnectionFailed = false; error = false; message = "已重新连接后台任务服务。" }
            // The service snapshot is authoritative. Reconnect never replays a UI intent.
            if previousInstance != nil && previousInstance != connectedServiceInstanceID {
                interfaceHandle = nil; interfaceSpec = nil
            }
            serviceRetryAt = .distantPast; serviceRetryDelay = 1; serviceRecoveryBeganAt = nil
            reportPowerServiceRecovery()
        } catch {
            guard generation == observedGeneration, workStopEpoch == stopEpoch else { return }
            if serviceRecoveryBeganAt == nil { serviceRecoveryBeganAt = Date() }
            serviceConnectionFailed = true; requestServiceMessage = error.localizedDescription
            snapshot = nil; active = nil; remoteTaskStatus = [:]; self.error = true; message = requestServiceMessage
            // A launch/reconnect is bounded and uses the existing approval. Do
            // not turn each short transport outage into another modal alert.
            if !serviceRecoveryEnabled || Date().timeIntervalSince(serviceRecoveryBeganAt!) >= 30 {
                reportPowerServiceFailure(message)
            }
        }
    }
    func chooseThroughService(_ mode: WorkMode, sleep: Bool, automatic: Bool, reconcilingRequests: Bool) async {
        guard !busy || mode == .normal else { return }
        generation += 1
        let revision = generation, epoch = workStopEpoch, transition = UUID()
        serviceTransitionOwner = transition; busy = true
        defer {
            if serviceTransitionOwner == transition { serviceTransitionOwner = nil; busy = false }
            onUpdate?()
        }
        if mode != .normal, !(await authorizeCoreWork(grantID: transition, revision: revision, epoch: epoch)) { return }
        guard coreIntentIsCurrent(revision: revision, epoch: epoch) else {
            await cancelCoreAuthorization(transition); return
        }
        do {
            let reply: ControlReply
            if sleep { reply = try await serviceCall(.init("sleep-now")) }
            else if mode == .normal { reply = try await serviceCall(.init("stop-all")) }
            else {
                var request = ControlMessage("core-mode", id: transition); request.mode = mode
                reply = try await serviceCall(request)
            }
            guard generation == revision, workStopEpoch == epoch else { await refreshTaskService(); return }
            adoptServiceReply(reply)
            error = false; pending = nil
            message = sleep ? "已向系统发送休眠请求。" : mode == .normal ? (snapshot?.sleepDisabled == true ? "Orexin 已停止保活；系统防休眠仍处于开启状态。" : "已停止全部保活；运行中的命令继续。") : "后台核心已核验当前工作需求。"
        } catch {
            await cancelCoreAuthorization(transition)
            guard coreIntentIsCurrent(revision: revision, epoch: epoch) else { return }
            self.error = true; message = error.localizedDescription
        }
    }
    func disconnectInterface() async {
        interfaceHandle = nil; interfaceSpec = nil
        quitApplication?()
    }
    func submitServiceCommand(command: String, directory: String) async {
        do {
            let path = (directory as NSString).expandingTildeInPath
            var spec = WorkRequestSpec(title: "Command " + Date().formatted(date: .omitted, time: .standard), source: "command", teardown: .sleepOnSuccess)
            if let id = selectedWorkProfileID, let profile = profiles.profiles.first(where: { $0.id == id }) { spec = try profile.applying(to: spec, now: Date()) }
            var request = ControlMessage("command-start", spec: spec, id: UUID())
            request.command = command; request.directory = path
            adoptServiceReply(try await serviceCall(request)); jobStatus = "命令已交给后台服务"; convenienceMessage = ""
        } catch { convenienceMessage = error.localizedDescription; jobStatus = convenienceMessage }
        onUpdate?()
    }
}
