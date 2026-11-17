// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import WakeMacCore

struct CoreStatisticsSnapshot: Codable {
    var awakeSeconds: Double
    var lidSeconds: Double
    var activations: Int
}
struct CoreSessionSnapshot: Codable {
    var active: Bool
    var starting: Bool
    var status: String
    var deadline: Date?
    var effects: SessionEffectReport
    var downloadProgress: Double?
    var overrides: SessionBehaviorOverride?
    var cursor: Bool
    var preventDisplay: Bool
    var preventSaver: Bool
}
struct CoreRuntimeSnapshot: Codable {
    var session: CoreSessionSnapshot
    var manualMode: WorkMode?
    var sessionMode: WorkMode?
    var triggerMode: WorkMode?
    var triggerRuleID: UUID?
    var triggerSummary: String
    var timer: Date?
    var screenBehavior: WorkScreenBehavior?
    var statistics: CoreStatisticsSnapshot?
}
/// Explicit UI intents are never persisted or replayed after reconnecting.
struct CoreControlIntent: Codable {
    var condition: SessionEndCondition?
    var duration: Double?
    var date: Date?
    var process: DiscoveredProcess?
    var behavior: WorkScreenBehavior?
    var display: Bool?
    var saver: Bool?
    var cursor: Bool?
    var drives: Bool?
}
extension AppModel {
    func resetCoreStatistics() async {
        if serviceSocket != nil { _ = await mutateCore("core-statistics-reset") }
        else { behavior.resetStatistics(); onUpdate?() }
    }
    func restartCoreService() async {
        await stopCoreService()
        guard corePaused else { return }
        // The old service acknowledges before removing its endpoint.
        try? await Task.sleep(for: .milliseconds(300))
        await connectTaskService()
    }
    func stopCoreService() async {
        guard !busy else { return }
        generation += 1; busy = true
        defer { busy = false; onUpdate?() }
        let previousRecovery = serviceRecoveryEnabled
        serviceRecoveryEnabled = false
        do {
            adoptServiceReply(try await serviceCall(.init("service-stop")))
            corePaused = true; serviceInfo = nil; connectedServiceInstanceID = nil
            error = false; message = "后台核心已停止。"; requestServiceMessage = message
        } catch {
            serviceRecoveryEnabled = previousRecovery
            self.error = true; message = error.localizedDescription
        }
        onUpdate?()
    }
    var coreRuntimeSnapshot: CoreRuntimeSnapshot {
        .init(session: .init(active: sessions.isActive, starting: sessions.isStarting, status: sessions.status,
                             deadline: sessions.deadline, effects: sessions.effectReport,
                             downloadProgress: sessions.downloadProgressPercent, overrides: sessions.effectOverrides,
                             cursor: sessions.moveCursor, preventDisplay: sessions.effectivePreventDisplaySleep, preventSaver: sessions.effectivePreventScreenSaver),
              manualMode: manualWorkMode, sessionMode: sessionWorkMode, triggerMode: triggerOwnedMode,
              triggerRuleID: triggerOwnedRuleID, triggerSummary: triggerSummary, timer: automation.deadline,
              screenBehavior: active.flatMap { $0 == .normal ? nil : workScreen.behavior(for: $0) },
              statistics: .init(awakeSeconds: behavior.awakeSeconds, lidSeconds: behavior.lidSeconds, activations: behavior.activations))
    }
    @discardableResult func mutateCore(_ operation: String, mode: WorkMode? = nil, enabled: Bool? = nil,
                                      minutes: Double? = nil, intent: CoreControlIntent? = nil) async -> Bool {
        do {
            guard !coreUpgradeRequired else { throw ModeError("后台核心需要更新；请先结束当前工作，再重新启动核心。") }
            var request = ControlMessage(operation); request.mode = mode; request.enabled = enabled
            request.document = try ControlCoding.encode(intent ?? CoreControlIntent(duration: minutes))
            let reply = try await serviceCall(request)
            adoptServiceReply(reply)
            if let outcome = reply.outcomeMessage { message = outcome }
            error = false; return true
        } catch { self.error = true; message = error.localizedDescription; onUpdate?(); return false }
    }
    func coreIntentIsCurrent(revision: Int, epoch: Int) -> Bool {
        generation == revision && workStopEpoch == epoch
    }
    func cancelCoreAuthorization(_ grantID: UUID) async {
        _ = try? await serviceCall(.init("unlocked-cancel", id: grantID))
    }
    func startCoreSession() async {
        generation += 1
        let revision = generation, epoch = workStopEpoch, grantID = UUID()
        let intent = CoreControlIntent(condition: sessions.endCondition, duration: sessions.durationMinutes,
                                       date: sessions.endDate, process: sessions.selectedProcess)
        guard await authorizeCoreWork(grantID: grantID, revision: revision, epoch: epoch) else { return }
        guard coreIntentIsCurrent(revision: revision, epoch: epoch) else {
            await cancelCoreAuthorization(grantID); return
        }
        var request = ControlMessage("core-session-start", id: grantID)
        do {
            request.document = try ControlCoding.encode(intent)
            let reply = try await serviceCall(request)
            guard coreIntentIsCurrent(revision: revision, epoch: epoch) else { await refreshTaskService(); return }
            adoptServiceReply(reply); error = false
        } catch {
            await cancelCoreAuthorization(grantID)
            guard coreIntentIsCurrent(revision: revision, epoch: epoch) else { return }
            self.error = true; message = error.localizedDescription
        }
    }
    func authorizeCoreWork(grantID: UUID, revision: Int, epoch: Int) async -> Bool {
        guard !coreUpgradeRequired else {
            error = true; message = "后台核心需要更新；请先结束当前工作，再重新启动核心。"; return false
        }
        guard unlockedWorkEnabled else { return true }
        func ensureCurrent() throws {
            guard coreIntentIsCurrent(revision: revision, epoch: epoch) else { throw CancellationError() }
        }
        do {
            var prepare = ControlMessage("unlocked-prepare", id: grantID)
            prepare.owner = LocalProcessIdentity.capture(pid: getpid())
            let prepared = try await serviceCall(prepare)
            try ensureCurrent()
            if prepared.unlockedWorkAuthorized != true {
                try await UnlockedWorkAuthentication.authorize(credentials: unlockedCredentials,
                    requestPassword: requestUnlockedWorkPassword,
                    renew: {
                        try ensureCurrent()
                        _ = try await self.serviceCall(.init("unlocked-ready", id: grantID))
                        try ensureCurrent()
                    },
                    apply: { password in try ensureCurrent(); try await self.disableUnlockedWorkScreenLock(password) },
                    verify: {
                        try ensureCurrent()
                        _ = try await self.serviceCall(.init("unlocked-finish", id: grantID))
                    })
            }
            try ensureCurrent()
            return true
        } catch {
            await cancelCoreAuthorization(grantID)
            guard coreIntentIsCurrent(revision: revision, epoch: epoch) else { return false }
            self.error = true; message = error.localizedDescription; return false
        }
    }
    func handleCoreControl(_ request: ControlMessage) async throws -> ControlReply {
        guard isTaskService else { throw ModeError("独立核心尚未运行，请重新启动后台服务。") }
        let intent = try request.document.map { try ControlCoding.decode(CoreControlIntent.self, from: $0) } ?? .init()
        let consumesGrant = request.operation == "core-session-start" || (request.operation == "core-mode" && request.mode != .normal)
        if consumesGrant, let pending = pendingUnlockedGrantID, pending != request.id {
            throw ModeError("本次授权已被其他操作取代，请重新开始工作。")
        }
        switch request.operation {
        case "core-statistics-reset": behavior.resetStatistics()
        case "core-mode":
            guard let mode = request.mode else { throw ModeError("缺少工作模式。") }
            await choose(mode)
        case "core-session-start":
            guard !sessions.isActive, !sessions.isStarting else { throw ModeError("工作会话已经运行。") }
            if let condition = intent.condition { sessions.endCondition = condition }
            if let duration = intent.duration { sessions.durationMinutes = duration }
            if let date = intent.date { sessions.endDate = date }
            sessions.selectedProcess = intent.process
            await sessions.start()
            guard sessions.isActive else { throw ModeError(sessions.status) }
        case "core-session-end": await sessions.end()
        case "core-session-extend":
            guard let minutes = intent.duration, sessions.extend(minutes: minutes) else { throw ModeError(sessions.status) }
        case "core-effects":
            message = "工作效果设置已更新。"
            if let behavior = intent.behavior { await setWorkScreenBehavior(behavior) }
            if let display = intent.display { await changeDisplayPrevention(display) }
            if let saver = intent.saver { await changeScreenSaverPrevention(saver) }
            if let cursor = intent.cursor { sessions.moveCursor = cursor }
            if let drives = intent.drives { sessions.driveAlive = drives }
            await applyWorkScreenPolicy(now: Date())
        case "core-triggers":
            guard let enabled = request.enabled else { throw ModeError("缺少规则设置。") }
            await setTriggersEnabled(enabled)
        case "core-lid":
            guard let enabled = request.enabled else { throw ModeError("缺少合盖设置。") }
            await changeSessionLidMode(enabled)
        case "core-timer":
            if let date = intent.date { scheduleRestore(at: date) } else { cancelTimer() }
        default: throw ModeError("未知核心操作。")
        }
        if consumesGrant, request.id == pendingUnlockedGrantID {
            pendingUnlockedGrantID = nil; pendingUnlockedOwner = nil; pendingUnlockedDeadline = nil
        }
        var reply = taskControlReply()
        reply.outcomeMessage = message
        if error || pending != nil { reply.ok = false; reply.error = message }
        return reply
    }
}
