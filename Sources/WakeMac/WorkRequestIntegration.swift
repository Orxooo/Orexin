// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import WakeMacCore

extension AppModel {
    var legacyWorkMode: WorkMode? { manualWorkMode ?? sessionWorkMode ?? triggerOwnedMode }
    func aggregateMode(including mode: WorkMode? = nil) -> WorkMode {
        let modes = [mode, legacyWorkMode, workRequests.demand?.mode].compactMap { $0 }
        return modes.contains(.background) ? .background : modes.contains(.desk) ? .desk : .normal
    }
    func updateRequestScreenPolicy() {
        guard let demand = workRequests.demand else { workScreen.requestBehavior = nil; return }
        let requested: WorkScreenBehavior = demand.screen == .awake ? .normalBrightness : demand.screen == .dim ? .dim : .systemIdle
        if let legacy = legacyWorkMode {
            let base = workScreen.ownBehavior(for: legacy)
            if base == .normalBrightness || requested == .normalBrightness { workScreen.requestBehavior = .normalBrightness }
            else if base == .dim || requested == .dim { workScreen.requestBehavior = .dim }
            else { workScreen.requestBehavior = .systemIdle }
        } else { workScreen.requestBehavior = requested }
    }
    func saveWorkRequests() {
        observeWorkOutcomes(now: Date())
        guard let requestHistoryURL else { return }
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workRequests.records)
            try FileManager.default.createDirectory(at: requestHistoryURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: requestHistoryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestHistoryURL.path)
        } catch { requestServiceMessage = "任务记录保存失败：" + error.localizedDescription }
    }
    func recoverWorkRequests(from url: URL) {
        requestHistoryURL = url
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            workRequests = WorkRequestLedger(recovering: try decoder.decode([WorkRequestRecord].self, from: Data(contentsOf: url)), now: Date())
            observedWorkEnds = Set(workRequests.records.map(\.id))
            saveWorkRequests()
        } catch { requestServiceMessage = "无法恢复任务记录；未重放保活：" + error.localizedDescription }
    }
    /// Global user/safety actions revoke requests, never the user's command processes.
    func overrideWorkRequests(reason: String) {
        cancelPendingPlans()
        workStopEpoch += 1
        policyHooks.cancelAll()
        workRequests.stopAll(reason: reason, now: Date())
        manualWorkMode = nil; sessionWorkMode = nil
        requestCountdownMode = nil; workScreen.requestBehavior = nil
        sessions.requestedScreenSaverPrevention = nil
        saveWorkRequests()
    }
    @discardableResult func registerWork(_ spec: WorkRequestSpec, handle: WorkRequestHandle = .init(), now: Date = Date()) async throws -> WorkRequestHandle {
        if serviceSocket != nil {
            let reply = try await serviceCall(.init("register", handle: handle, spec: spec))
            adoptServiceReply(reply); return reply.handle ?? handle
        }
        var spec = spec
        let selectedProfile: WorkProfile?
        if let id = spec.profileID {
            let captured = workRequests.records.contains(where: { $0.id == handle.id && $0.spec.profileID == id }) ? requestProfiles[handle.id] : nil
            guard let profile = captured ?? profiles.profiles.first(where: { $0.id == id }) else { throw ModeError("Unknown work profile") }
            selectedProfile = profile
            // A retry retains the original effective deadline and captured policy.
            if let existing = workRequests.records.first(where: { $0.id == handle.id }), existing.spec.profileID == id {
                spec = try (requestProfiles[handle.id] ?? profile).applying(to: spec, now: existing.createdAt)
            } else { spec = try profile.applying(to: spec, now: now) }
        } else { selectedProfile = nil }
        guard !requestStopInProgress else { throw ModeError("Global work teardown is in progress; register again after it finishes") }
        guard !thermalProtectionRequired, !thermalCleanupPending else { throw ModeError("Thermal protection is active") }
        let stopEpoch = workStopEpoch
        // A local client cannot cause or bypass a new authentication prompt.
        if spec.source == "external", unlockedWorkEnabled && !verifiedWork {
            throw ModeError("Start and authorize unlocked work in Orexin before registering an external request")
        }
        if workRequests.active.isEmpty, legacyWorkMode == nil, verifiedWork, requestCountdownMode == nil {
            manualWorkMode = active
        }
        if workRequests.active.isEmpty && legacyWorkMode == nil && active == .normal { automation.resetBatterySession() }
        let inserted = !workRequests.records.contains { $0.id == handle.id }
        let registered = try workRequests.register(spec, handle: handle, now: now)
        if inserted, let profile = selectedProfile {
            requestProfiles[registered.id] = profile
            if profiles.hooksEnabled(profile) { requestHookApprovals[registered.id] = profiles.approvals[profile.id.uuidString] }
        }
        if automation.jobSleepAt != nil || requestCountdownMode != nil { automaticSleepRevision += 1 }
        automation.cancelJobSleep(); requestCountdownMode = nil
        saveWorkRequests()
        do {
            try Task.checkCancellation()
            await reconcileWorkRequests()
            // Another registration or manual action can arrive during native verification.
            while busy { try await Task.sleep(for: .milliseconds(20)) }
            try Task.checkCancellation()
            await reconcileWorkRequests()
            await reapWorkRequests(now: Date())
            try Task.checkCancellation()
            // Reaping another request can itself await native teardown. Validate this
            // request again without an intervening await before acknowledging it.
            if let current = workRequests.active.first(where: { $0.id == registered.id }) {
                if [current.leaseExpiresAt, current.spec.deadline].compactMap({ $0 }).contains(where: { Date() >= $0 }) {
                    _ = try workRequests.release(id: registered.id, state: .expired, reason: "Deadline or heartbeat lease expired during activation", now: Date())
                } else if current.spec.process?.isAlive == false {
                    _ = try workRequests.release(id: registered.id, state: .lost, reason: "Owner process disappeared during activation", now: Date())
                }
            }
            guard stopEpoch == workStopEpoch, !requestStopInProgress,
                  workRequests.active.contains(where: { $0.id == registered.id }), requestSatisfied(spec) else {
                _ = try? workRequests.release(id: registered.id, state: .rejected, reason: requestUnsatisfiedReason(spec), now: Date())
                throw ModeError("Request was not activated: " + (workRequests.records.first { $0.id == registered.id }?.reason ?? requestUnsatisfiedReason(spec)))
            }
        } catch {
            if inserted { _ = try? workRequests.release(id: registered.id, reason: "Registration cancelled before acknowledgement", now: Date()) }
            saveWorkRequests(); await reconcileWorkRequests()
            throw error
        }
        record("工作请求已登记：" + spec.title); onUpdate?()
        return registered
    }
    func requestUnsatisfiedReason(_ spec: WorkRequestSpec) -> String {
        if busy { return "Verifying power state" }
        if !verifiedWork { return message }
        if spec.mode == .background && active != .background { return "Background mode is not verified" }
        return "Display requirement is not verified: " + sessions.effectReport.display + " · " + workScreen.status
    }
    func requestSatisfied(_ spec: WorkRequestSpec) -> Bool {
        if serviceSocket != nil { return remoteTaskStatus.values.contains { $0.request.spec == spec && $0.satisfied } }
        guard verifiedWork, spec.mode != .background || active == .background else { return false }
        guard let active else { return false }
        let screen = workScreen.behavior(for: active)
        return spec.screen == .idle || (sessions.effectReport.displayAssertionActive && workScreen.isVerified(screen)
            && (spec.screen == .dim ? screen.keepsDisplayActive : screen == .normalBrightness))
    }
    func completeWork(_ handle: WorkRequestHandle, exitCode: Int32, now: Date = Date()) async throws {
        if serviceSocket != nil { adoptServiceReply(try await serviceCall(.init("complete", handle: handle, exitCode: exitCode))); return }
        let teardown = try workRequests.complete(handle, exitCode: exitCode, now: now)
        saveWorkRequests()
        await finishWorkMutation(teardown, now: now)
    }
    func releaseWork(id: UUID, now: Date = Date()) async {
        if serviceSocket != nil {
            do { adoptServiceReply(try await serviceCall(.init("release-user", id: id))) }
            catch { requestServiceMessage = error.localizedDescription }
            return
        }
        guard let teardown = try? workRequests.release(id: id, reason: "User released this request; command continues", now: now) else {
            saveWorkRequests(); await reconcileWorkRequests(); return
        }
        saveWorkRequests(); await finishWorkMutation(teardown, now: now)
    }
    func reapWorkRequests(now: Date) async {
        let previous = workRequests.records
        let teardown = workRequests.reap(now: now, processAlive: { $0.isAlive })
        guard workRequests.records != previous else { return }
        let newlyExpired = workRequests.records.filter { item in
            item.state == .expired && previous.contains { $0.id == item.id && $0.state == .active }
        }
        for item in newlyExpired {
            notices.post(.leaseExpired, title: "工作保活请求已到期",
                         body: item.spec.title + "：期限或心跳租约已到期，已撤销此请求的保活需求，正在核验电源状态；其他工作请求可能仍在运行。",
                         id: "expired.\(item.id.uuidString)", at: now)
        }
        saveWorkRequests(); await finishWorkMutation(teardown, now: now)
    }
    func finishWorkMutation(_ teardown: RequestTeardown?, now: Date) async {
        if teardown == .sleepOnSuccess, legacyWorkMode == nil, workRequests.active.isEmpty, verifiedWork {
            requestCountdownMode = active
            automation.scheduleJobSleep(now: now)
            record("全部工作请求成功；60 秒后休眠，可取消。")
        }
        if teardown == .restore { requestCountdownMode = nil }
        await reconcileWorkRequests()
        onUpdate?()
    }
    func reconcileWorkRequests() async {
        if serviceSocket != nil {
            await chooseThroughService(aggregateMode(), sleep: false, automatic: true, reconcilingRequests: true)
            return
        }
        requestReconcileNeeded = true
        guard !busy, !requestReconcileRunning else { return }
        requestReconcileRunning = true
        defer { requestReconcileRunning = false }
        repeat {
            requestReconcileNeeded = false
            let target = aggregateMode(including: requestCountdownMode)
            updateRequestScreenPolicy()
            if active != target || error || pending != nil {
                await choose(target, automatic: true, startupRecovery: true, reconcilingRequests: true)
            } else { await applyWorkScreenPolicy(now: Date()) }
        } while requestReconcileNeeded && !busy
    }
    func endOwnedSession(conditionMet: Bool) async {
        if sessionWorkMode != nil {
            sessions.effectOverrides = nil
            workScreen.runtimeBehavior = nil
        }
        sessionWorkMode = nil
        if workRequests.active.isEmpty && manualWorkMode == nil && triggerOwnedMode == nil {
            await choose(.normal, sleep: conditionMet, automatic: true)
        } else {
            await reconcileWorkRequests()
            record("会话已结束；其他工作请求继续。")
        }
    }
}
