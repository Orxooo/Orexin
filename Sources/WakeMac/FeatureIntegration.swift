// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation
import WakeMacCore

extension AppModel {
    func makeTriggerController() -> TriggerController {
        let controller = TriggerController(preferences: preferences, source: triggerSource)
        controller.arbitrationContextProvider = { [weak self] in self?.triggerArbitrationContext ?? .init() }
        return controller
    }
    var triggerArbitrationContext: TriggerArbitrationContext {
        TriggerArbitrationContext(masterEnabled: triggers.enabled, suppressedRuleIDs: suppressedTriggerIDs,
                                  sessionActive: sessions.isActive || sessions.isStarting,
                                  manualWorkActive: triggerOwnedMode == nil && manualWorkMode != nil,
                                  safetyBlockReason: thermalProtectionRequired || thermalCleanupPending ? "温度保护正在生效。" : nil)
    }

    func handleSystemWillSleep() async {
        // A closed-lid power transition can emit willSleep. It does not identify
        // a user's explicit Sleep action and must not revoke background work.
        guard !busy, active != .background, snapshot?.backgroundLeaseActive != true else { return }
        if sessions.isActive { await sessions.end() }
        else if keepsAwake, triggerOwnedMode == nil { await choose(.normal) }
    }
    func makeSessionController() -> SessionController {
        let controller = SessionController(preferences: preferences, effects: sessionEffects)
        controller.workingProvider = { [weak self] in self?.verifiedWork == true }
        controller.configuredScreenPolicyProvider = { [weak self, weak controller] in
            guard let self, let controller else { return false }
            return (controller.defaultMode == .background ? self.workScreen.background : self.workScreen.desktop).keepsDisplayActive
        }
        controller.onBegin = { [weak self] mode in
            guard let self, !self.busy else { return false }
            self.suppressCurrentTriggers()
            self.sessions.effectOverrides = nil
            self.workScreen.runtimeBehavior = nil
            self.manualWorkMode = nil; self.sessionWorkMode = mode
            await self.choose(mode, automatic: true)
            let verified = self.verifiedWork && (mode != .background || self.active == .background)
            if !verified { self.sessionWorkMode = nil }
            if verified { self.featureNotificationHandler?("工作会话已开始：" + mode.title, .sessionStart) }
            return verified
        }
        controller.onEnd = { [weak self] in
            guard let self else { return }
            await self.endOwnedSession(conditionMet: false)
            if self.active == .normal, !self.error, self.pending == nil {
                self.featureNotificationHandler?("工作会话已结束，已恢复正常休眠。", .sessionEnd)
            }
        }
        controller.onConditionEnd = { [weak self] in
            guard let self else { return }
            await self.endOwnedSession(conditionMet: true)
            if self.active == .normal, !self.error, self.pending == nil {
                self.featureNotificationHandler?("会话条件已满足，已恢复正常模式并请求休眠与锁定。", .sessionEnd)
            }
        }
        controller.onExtended = { [weak self] minutes in
            guard let self else { return }
            let text = "工作会话已延长 \(minutes.formatted()) 分钟。"
            self.record(text)
            self.featureNotificationHandler?(text, .sessionExtended)
            self.onUpdate?()
        }
        return controller
    }
    func suppressCurrentTriggers() {
        if triggerOwnedRuleID != nil { workScreen.runtimeBehavior = nil }
        if let id = triggerOwnedRuleID {
            record("自动规则已抑制：手动操作、会话或保护策略优先。",
                   context: HistoryContext(kind: .rule, requestIDs: workRequests.active.map(\.id), ruleID: id, mode: active?.rawValue))
        }
        suppressedTriggerIDs.formUnion(triggers.rules.filter(\.enabled).map(\.id))
        triggerOwnedMode = nil
        triggerOwnedRuleID = nil; appliedTriggerBehavior = nil
        triggerRuntimeMode = nil
        triggerSummary = "手动操作优先；当前规则解除后可再次触发"
        triggers.updateArbitration(triggerArbitrationContext)
    }
    func tickFeatures(now date: Date, battery reading: BatteryReading?, thermalAlreadyChecked: Bool = false) async {
        guard !featureTickRunning else { return }
        featureTickRunning = true
        defer { featureTickRunning = false }
        if !thermalAlreadyChecked, await protectFromThermalPressure() { return }
        await applyWorkScreenPolicy(now: date)
        await idlePolicy.tick()
        guard !busy, pending == nil, date.timeIntervalSince(lastFeatureSample) >= 5 else { return }
        lastFeatureSample = date
        let revision = generation
        let matching = await triggers.matchingRules(now: date, battery: reading)
        guard generation == revision, !busy, pending == nil else { return }
        suppressedTriggerIDs.formIntersection(triggers.assertedRuleIDs)
        triggers.updateArbitration(triggerArbitrationContext)
        guard !sessions.isActive, !sessions.isStarting else { triggerSummary = "当前会话优先于自动触发"; return }
        let available = matching.filter { !suppressedTriggerIDs.contains($0.id) }
        if let desired = available.first {
            if triggerOwnedMode == nil && manualWorkMode != nil { triggerSummary = "保留当前手动工作模式"; return }
            if triggerOwnedRuleID != desired.id { triggerRuntimeMode = nil }
            let targetMode = triggerRuntimeMode ?? desired.mode
            if triggerOwnedMode != targetMode || active != aggregateMode(including: targetMode) {
                triggerOwnedMode = targetMode
                await choose(targetMode, automatic: true)
                guard verifiedWork, targetMode != .background || active == .background else {
                    triggerOwnedMode = nil
                    suppressedTriggerIDs.formUnion(available.map(\.id))
                    triggers.updateArbitration(triggerArbitrationContext)
                    return
                }
                triggerOwnedMode = targetMode
            }
            let behavior = SessionBehaviorOverride(display: desired.preventDisplaySleep, saver: desired.preventScreenSaver)
            if triggerOwnedRuleID != desired.id || appliedTriggerBehavior != behavior {
                let previousRuleID = triggerOwnedRuleID
                triggerOwnedRuleID = desired.id; appliedTriggerBehavior = behavior
                if previousRuleID != desired.id {
                    record((previousRuleID == nil ? "自动触发：" : "自动规则接管：") + desired.name,
                           context: HistoryContext(kind: .rule, requestIDs: workRequests.active.map(\.id), ruleID: desired.id, mode: active?.rawValue))
                }
                sessions.effectOverrides = behavior
                if let display = desired.preventDisplaySleep {
                    workScreen.runtimeBehavior = display ? (targetMode == .background ? .dim : .normalBrightness) : .systemIdle
                } else if desired.preventScreenSaver == true {
                    workScreen.runtimeBehavior = targetMode == .background ? .dim : .normalBrightness
                } else { workScreen.runtimeBehavior = nil }
                await applyWorkScreenPolicy(now: date)
                await sessions.tick(now: date)
                featureNotificationHandler?("自动触发：" + desired.name, .triggerChange)
            }
            triggerSummary = "自动触发：" + desired.name
        } else if triggerOwnedMode != nil {
            // A rule naturally ending is not a manual veto. It may run again
            // when its conditions next become true.
            let endedRuleID = triggerOwnedRuleID
            triggerOwnedMode = nil; triggerOwnedRuleID = nil; appliedTriggerBehavior = nil
            triggerRuntimeMode = nil; sessions.effectOverrides = nil
            workScreen.runtimeBehavior = nil
            await reconcileWorkRequests()
            if let endedRuleID {
                record("自动规则结束：条件或时间要求已解除。",
                       context: HistoryContext(kind: .rule, requestIDs: workRequests.active.map(\.id), ruleID: endedRuleID, mode: active?.rawValue))
            }
            triggerSummary = "规则条件已解除，恢复正常休眠"
            featureNotificationHandler?(triggerSummary, .triggerChange)
        } else { triggerSummary = matching.isEmpty ? triggers.status : "手动操作优先；等待规则条件解除" }
        let normalRevision = generation
        if active == .normal, !busy, pending == nil, !jobRunning,
           await workScreen.normalSleepIsDue(state: DisplayState.read(), onBattery: reading?.onBattery == true, now: date),
           generation == normalRevision, active == .normal, !busy, pending == nil {
            record("正常模式闲置时间已到，请求休眠与锁定。")
            await choose(.normal, sleep: true, automatic: true)
        }
    }
}
