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
        if let service = reply.service {
            if let previous = connectedServiceInstanceID, previous != service.instanceID {
                interfaceHandle = nil; interfaceSpec = nil
            }
            connectedServiceInstanceID = service.instanceID
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
        serviceRecoveryEnabled = true
        do {
            let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            let socket = serviceSocket ?? TaskServiceLauncher.socketPath
            let reply = try await launchTaskService(executable, socket)
            adoptServiceReply(reply); error = false; message = "已连接后台任务服务。"
        } catch {
            self.error = true; message = error.localizedDescription; requestServiceMessage = message
            reportPowerServiceFailure(message)
        }
    }
    func refreshTaskService(renew: Bool = false) async {
        guard !serviceRefreshRunning else { return }
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
            let replaced = previousInstance != nil && previousInstance != connectedServiceInstanceID
            if replaced, unlockedWorkEnabled {
                // A password-free recovery must never invent a new lock-off grant.
                interfaceHandle = nil; interfaceSpec = nil
                manualWorkMode = nil; sessionWorkMode = nil; triggerOwnedMode = nil
            } else if replaced, stopEpoch == workStopEpoch, !busy, let mode = legacyWorkMode {
                await chooseThroughService(mode, sleep: false, automatic: true, reconcilingRequests: true)
            } else if let handle = interfaceHandle {
                if !reply.tasks.contains(where: { $0.request.id == handle.id && $0.request.state == .active }) {
                    // Same-instance revocation/expiry is authoritative. Never undo
                    // a CLI stop or safety teardown by registering the GUI again.
                    interfaceHandle = nil; interfaceSpec = nil
                    manualWorkMode = nil; sessionWorkMode = nil; triggerOwnedMode = nil
                } else if renew {
                    _ = try await serviceCall(.init("heartbeat", handle: handle))
                }
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
        let attemptStarted = Date()
        if busy && mode != .normal { return }
        // The timer already renews the lease and reads service state. Reconcile
        // unchanged, verified work without publishing a user-visible transition.
        if automatic, reconcilingRequests, !sleep, verifiedWork, !serviceConnectionFailed,
           let desired = legacyWorkMode, desired != .normal, let handle = interfaceHandle,
           workRequests.active.contains(where: { $0.id == handle.id }),
           interfaceSpec == interfaceRequestSpec(for: desired) { return }
        generation += 1
        let revision = generation, stopEpoch = workStopEpoch, transition = UUID()
        serviceTransitionOwner = transition
        busy = true; error = false; pending = nil
        defer {
            if serviceTransitionOwner == transition { serviceTransitionOwner = nil; busy = false }
            onUpdate?()
        }
        do {
            if !reconcilingRequests && (!automatic || mode == .normal) {
                sessions.effectOverrides = nil
                workScreen.runtimeBehavior = nil
            }
            if mode == .normal && !reconcilingRequests {
                interfaceHandle = nil; interfaceSpec = nil
                overrideWorkRequests(reason: "User or interface stopped all work")
                sessions.manualModeChanged(); suppressCurrentTriggers()
                let reply = try await serviceCall(.init(sleep ? "sleep-now" : "stop-all"))
                guard generation == revision else { return }
                adoptServiceReply(reply)
                sessions.screenPolicyPreventsSleep = nil
                sessions.requestedScreenSaverPrevention = nil
                message = sleep ? "已向系统发送休眠请求。" : "已停止全部保活；运行中的命令继续。"
                return
            }
            if !automatic { manualWorkMode = mode; sessionWorkMode = nil; suppressCurrentTriggers() }
            let desired = reconcilingRequests ? legacyWorkMode : legacyWorkMode ?? mode
            if let desired, desired != .normal {
                let status = try await serviceCall(.init("status"))
                guard generation == revision, workStopEpoch == stopEpoch else { return }
                adoptServiceReply(status)
                let spec = interfaceRequestSpec(for: desired)
                if interfaceSpec != spec || interfaceHandle == nil {
                    if unlockedWorkEnabled {
                        var prepare = ControlMessage("unlocked-prepare"); prepare.owner = LocalProcessIdentity.capture(pid: getpid())
                        let prepared = try await serviceCall(prepare)
                        guard generation == revision, workStopEpoch == stopEpoch else { return }
                        if prepared.unlockedWorkAuthorized != true {
                            do {
                                var password = try requestUnlockedWorkPassword()
                                defer { password.resetBytes(in: 0..<password.count) }
                                _ = try await serviceCall(.init("unlocked-ready"))
                                try await disableUnlockedWorkScreenLock(password)
                                _ = try await serviceCall(.init("unlocked-finish"))
                            } catch { _ = try? await serviceCall(.init("stop-all")); throw error }
                        }
                    }
                    guard generation == revision, workStopEpoch == stopEpoch else { return }
                    let handle = WorkRequestHandle(), previous = interfaceHandle
                    let registered = try await serviceCall(.init("interface-register", handle: handle, spec: spec))
                    guard generation == revision, workStopEpoch == stopEpoch else {
                        _ = try? await serviceCall(.init("complete", handle: handle, exitCode: 0))
                        return
                    }
                    connectedServiceInstanceID = registered.service?.instanceID
                    interfaceHandle = handle; interfaceSpec = spec
                    if let previous { _ = try? await serviceCall(.init("complete", handle: previous, exitCode: 0)) }
                } else { _ = try await serviceCall(.init("heartbeat", handle: interfaceHandle)) }
            } else if let handle = interfaceHandle {
                interfaceHandle = nil; interfaceSpec = nil
                _ = try await serviceCall(.init("complete", handle: handle, exitCode: 0))
            }
            // Registration, heartbeat and completion replies contain one task.
            // Read the full ledger before calculating effects from all owners.
            let final = try await serviceCall(.init("status"))
            guard generation == revision, workStopEpoch == stopEpoch else { return }
            adoptServiceReply(final)
            preferences.set(true, forKey: "orexin.HasConfiguredMode")
            message = "后台服务已核验当前工作需求。"
        } catch {
            guard generation == revision else { return }
            self.error = true; message = error.localizedDescription
            let failure = message
            await refreshTaskService()
            guard generation == revision else { return }
            if !notices.entries.contains(where: { $0.kind == .operationFailed && $0.date >= attemptStarted }) {
                notices.post(.operationFailed, title: "工作模式未通过核验", body: failure)
            }
            self.error = true; message = failure
        }
    }
    private func interfaceRequestSpec(for mode: WorkMode) -> WorkRequestSpec {
        let screen = workScreen.ownBehavior(for: mode)
        return WorkRequestSpec(title: "Orexin interface", source: "interface", mode: mode,
                               screen: screen == .normalBrightness ? .awake : screen == .dim ? .dim : .idle,
                               leaseSeconds: 15, process: LocalProcessIdentity.capture(pid: getpid()),
                               preventScreenSaver: screen.keepsDisplayActive && sessions.screenSaverChoice(keepingDisplayActive: true))
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
