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

extension AppModel {
    func serviceCall(_ message: ControlMessage) async throws -> ControlReply {
        guard let path = serviceSocket else { throw ModeError("No background service endpoint configured") }
        let reply = try await Task.detached { try LocalControlSocket.call(message, path: path) }.value
        guard reply.ok else { throw ModeError(reply.error ?? "Background service request failed") }
        guard reply.service?.protocolVersion == 1 else { throw ModeError("Quit the older Orexin application and start the current task service") }
        return reply
    }
    func adoptServiceReply(_ reply: ControlReply) {
        profiles.reload(); triggers.reload()
        workRequests = WorkRequestLedger(observing: reply.tasks.map(\.request))
        remoteTaskStatus = Dictionary(uniqueKeysWithValues: reply.tasks.map { ($0.request.id, $0) })
        runningCommandIDs = Set(reply.tasks.filter(\.commandRunning).map { $0.request.id })
        commandLogs = reply.commandLogs?.mapValues { URL(fileURLWithPath: $0) } ?? [:]
        jobRunning = !runningCommandIDs.isEmpty; servicePlans = reply.plans ?? []
        snapshot = reply.snapshot; active = reply.mode; serviceSleepAt = reply.sleepAt
        automation.observeServiceCountdowns(battery: reply.batterySleepAt, job: reply.sleepAt)
        if let data = reply.timeline, let events = try? ControlCoding.decode([HistoryEntry].self, from: data) {
            history = Array((events + historyStore.entries).sorted { $0.date > $1.date }.prefix(200))
        }
        if let service = reply.service { requestServiceMessage = LF("后台服务运行中 · PID %d", service.pid) }
        onUpdate?()
    }
    func connectTaskService() async {
        do {
            let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            let socket = serviceSocket ?? TaskServiceLauncher.socketPath
            let reply = try await Task.detached { try TaskServiceLauncher.start(executable: executable, socket: socket) }.value
            adoptServiceReply(reply); error = false; message = "已连接后台任务服务。"
        } catch { self.error = true; message = error.localizedDescription; requestServiceMessage = message }
    }
    func refreshTaskService(renew: Bool = false) async {
        guard !serviceRefreshRunning else { return }
        serviceRefreshRunning = true
        defer { serviceRefreshRunning = false }
        do {
            if renew, let handle = interfaceHandle {
                do { _ = try await serviceCall(.init("heartbeat", handle: handle)) }
                catch { interfaceHandle = nil; interfaceSpec = nil; manualWorkMode = nil; sessionWorkMode = nil; triggerOwnedMode = nil }
            }
            adoptServiceReply(try await serviceCall(.init("status")))
            if serviceConnectionFailed { serviceConnectionFailed = false; error = false; message = "已重新连接后台任务服务。" }
        } catch { serviceConnectionFailed = true; requestServiceMessage = error.localizedDescription; snapshot = nil; active = nil; remoteTaskStatus = [:]; self.error = true; message = requestServiceMessage }
    }
    func chooseThroughService(_ mode: WorkMode, sleep: Bool, automatic: Bool, reconcilingRequests: Bool) async {
        if busy && mode != .normal { return }
        busy = true; error = false; pending = nil
        defer { busy = false; onUpdate?() }
        do {
            if mode == .normal && !reconcilingRequests {
                interfaceHandle = nil; interfaceSpec = nil
                overrideWorkRequests(reason: "User or interface stopped all work")
                sessions.manualModeChanged(); suppressCurrentTriggers()
                adoptServiceReply(try await serviceCall(.init(sleep ? "sleep-now" : "stop-all")))
                message = sleep ? "已向系统发送休眠请求。" : "已停止全部保活；运行中的命令继续。"
                return
            }
            if !automatic { manualWorkMode = mode; sessionWorkMode = nil; suppressCurrentTriggers() }
            let desired = reconcilingRequests ? legacyWorkMode : legacyWorkMode ?? mode
            if let desired, desired != .normal {
                let screen = workScreen.runtimeBehavior ?? (desired == .background ? workScreen.background : workScreen.desktop)
                let spec = WorkRequestSpec(title: "Orexin interface", source: "interface", mode: desired,
                                           screen: screen == .normalBrightness ? .awake : screen == .dim ? .dim : .idle,
                                           leaseSeconds: 15, process: LocalProcessIdentity.capture(pid: getpid()))
                if interfaceSpec != spec || interfaceHandle == nil {
                    if unlockedWorkEnabled, snapshot?.lockPolicy != .off {
                        var prepare = ControlMessage("unlocked-prepare"); prepare.owner = LocalProcessIdentity.capture(pid: getpid())
                        _ = try await serviceCall(prepare)
                        do {
                            var password = try await UnlockedWorkAuthorization.requestPassword()
                            defer { password.resetBytes(in: 0..<password.count) }
                            _ = try await serviceCall(.init("unlocked-ready"))
                            try await Task.detached { [password] in try UnlockedWorkAuthorization.disableScreenLock(password: password) }.value
                            _ = try await serviceCall(.init("unlocked-finish"))
                        } catch { _ = try? await serviceCall(.init("stop-all")); throw error }
                    }
                    let handle = WorkRequestHandle(), previous = interfaceHandle
                    let reply = try await serviceCall(.init("interface-register", handle: handle, spec: spec))
                    interfaceHandle = handle; interfaceSpec = spec
                    if let previous { _ = try? await serviceCall(.init("complete", handle: previous, exitCode: 0)) }
                    adoptServiceReply(reply)
                } else { adoptServiceReply(try await serviceCall(.init("heartbeat", handle: interfaceHandle))) }
            } else if let handle = interfaceHandle {
                interfaceHandle = nil; interfaceSpec = nil
                adoptServiceReply(try await serviceCall(.init("complete", handle: handle, exitCode: 0)))
            } else { adoptServiceReply(try await serviceCall(.init("status"))) }
            preferences.set(true, forKey: "orexin.HasConfiguredMode")
            message = "后台服务已核验当前工作需求。"
        } catch { self.error = true; message = error.localizedDescription; await refreshTaskService(); self.error = true }
    }
    func disconnectInterface() async {
        if let handle = interfaceHandle { _ = try? await serviceCall(.init("complete", handle: handle, exitCode: 0)) }
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
