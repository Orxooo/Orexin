// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation
import WakeMacCore

extension AppModel {
    var verifiedWork: Bool { !busy && !error && pending == nil && (active == .desk || active == .background) && keepsAwake && snapshot.map { lockRequirement.accepts($0.lockPolicy) } == true }
    func changeDisplayPrevention(_ enabled: Bool) async {
        let mode = active == .background ? WorkMode.background : .desk
        workScreen.select(enabled ? (mode == .background ? .dim : .normalBrightness) : .systemIdle, for: mode)
        if verifiedWork { sessions.setDisplayPrevention(enabled) }
        else { sessions.preventDisplaySleep = enabled }
        await applyWorkScreenPolicy(now: Date())
        onUpdate?()
    }
    func setWorkScreenBehavior(_ behavior: WorkScreenBehavior) async {
        guard verifiedWork, let active else { return }
        workScreen.select(behavior, for: active)
        await applyWorkScreenPolicy(now: Date())
        onUpdate?()
    }
    func sleepDisplayNow() async {
        if serviceSocket != nil {
            do { adoptServiceReply(try await serviceCall(.init("display-sleep"))) } catch { message = error.localizedDescription }
            return
        }
        guard verifiedWork, !sessions.isStarting else { return }
        workScreen.runtimeBehavior = .immediateSleep
        await applyWorkScreenPolicy(now: Date())
        onUpdate?()
    }
    func selectWorkPreset(_ mode: WorkMode) async {
        if mode != .normal, sessions.isActive || triggerOwnedMode != nil {
            await changeSessionLidMode(mode == .background)
        } else { await choose(mode) }
    }
    func applyWorkScreenPolicy(now: Date) async {
        // A mode transition temporarily clears active/snapshot. Do not treat
        // that transient state as a failed session when a display wakes.
        guard !busy else { return }
        if serviceSocket != nil, interfaceHandle != nil { await chooseThroughService(aggregateMode(), sleep: false, automatic: true, reconcilingRequests: true) }
        updateRequestScreenPolicy()
        if verifiedWork, let active {
            sessions.screenPolicyPreventsSleep = workScreen.behavior(for: active).keepsDisplayActive
        } else { sessions.screenPolicyPreventsSleep = nil }
        await sessions.tick(now: now)
        let state = DisplayState.read()
        observeDisplay(state)
        await workScreen.tick(mode: active, working: verifiedWork, state: state,
                              onBattery: battery?.onBattery == true, now: now)
    }
    func changeScreenSaverPrevention(_ enabled: Bool) async {
        if verifiedWork { sessions.setScreenSaverPrevention(enabled) }
        else { sessions.preventScreenSaver = enabled }
        await sessions.tick(now: Date())
        onUpdate?()
    }
    func setTriggersEnabled(_ enabled: Bool) async {
        triggers.enabled = enabled
        if !enabled, triggerOwnedMode != nil, !sessions.isActive {
            triggerOwnedMode = nil; triggerOwnedRuleID = nil; appliedTriggerBehavior = nil
            triggerRuntimeMode = nil; sessions.effectOverrides = nil
            await reconcileWorkRequests()
        }
        if enabled { suppressedTriggerIDs.removeAll() }
        lastFeatureSample = .distantPast
        await tickFeatures(now: Date(), battery: battery)
    }
    func changeSessionLidMode(_ enabled: Bool) async {
        guard !busy, !sessions.isStarting else { return }
        if sessions.isActive || triggerOwnedMode != nil {
            let target: WorkMode = enabled ? .background : .desk
            if sessions.isActive { sessionWorkMode = target }
            if triggerOwnedMode != nil { triggerOwnedMode = target }
            await choose(target, automatic: true)
            if verifiedWork, active == target, triggerOwnedMode != nil {
                triggerRuntimeMode = target; triggerOwnedMode = target
            }
        } else { await setRunsWithLidClosed(enabled) }
    }
    func performShortcut(_ id: UInt32) async {
        guard !busy, !sessions.isStarting else { return }
        switch id {
        case 1: await selectWorkPreset(.background)
        case 2: await selectWorkPreset(.desk)
        case 3: await choose(.normal)
        case 4:
            if verifiedWork { await choose(.normal) }
            else { await beginDefaultSession() }
        case 5: await changeDisplayPrevention(!sessions.effectivePreventDisplaySleep)
        case 6: await changeScreenSaverPrevention(!sessions.effectivePreventScreenSaver)
        case 7: await changeSessionLidMode(!runsWithLidClosed)
        case 8:
            let extended = sessions.extend(minutes: 15)
            record(extended ? "快捷键：会话已延长 15 分钟。" : sessions.status)
            onUpdate?()
        case 9: openMenu?()
        case 10, 11:
            if verifiedWork { await choose(.normal) }
            sessions.endCondition = id == 10 ? .duration : .indefinite
            sessions.durationMinutes = behavior.defaultMinutes
            await sessions.start()
        default: break
        }
    }
}

/// The dictionary and the UI share the same verified paths; no script can alter authentication.
enum ScriptControlAction: String, CaseIterable {
    case active = "session is active", remaining = "session time remaining"
    case displayAllowed = "display sleep allowed", allowDisplay = "allow display sleep", preventDisplay = "prevent display sleep"
    case saverAllowed = "screen saver allowed", allowSaver = "allow screen saver", preventSaver = "prevent screen saver"
    case closedEnabled = "closed display mode enabled", enableClosed = "enable closed display mode", disableClosed = "disable closed display mode"
    case isTrigger = "session is trigger", triggersEnabled = "triggers are enabled", enableTriggers = "enable triggers", disableTriggers = "disable triggers"
    case driveEnabled = "drive alive is enabled", enableDrive = "enable drive alive", disableDrive = "disable drive alive"
    case extend = "extend session"

    @MainActor func perform(model: AppModel, arguments: [String: Any] = [:]) async throws -> Any {
        if self == .extend {
            guard let number = arguments["minutes"] as? NSNumber, number.doubleValue.isFinite,
                  (1...10080).contains(number.doubleValue) else { throw ModeError("延长时长须为 1–10080 分钟。") }
            guard model.sessions.extend(minutes: number.doubleValue) else { throw ModeError(model.sessions.status) }
            model.onUpdate?(); return model.sessions.status
        }
        switch self {
        case .active: await model.refresh(); return model.verifiedWork
        case .remaining:
            guard model.verifiedWork else { return -3 }
            if let end = model.sessions.deadline { return max(0, Int(ceil(end.timeIntervalSinceNow))) }
            if model.triggerOwnedMode != nil { return -1 }
            return model.sessions.isActive && [.application, .process, .download].contains(model.sessions.endCondition) ? -2 : 0
        case .displayAllowed: return !model.sessions.effectivePreventDisplaySleep
        case .allowDisplay: await model.changeDisplayPrevention(false)
        case .preventDisplay: await model.changeDisplayPrevention(true)
        case .saverAllowed: return !model.sessions.effectivePreventScreenSaver
        case .allowSaver: await model.changeScreenSaverPrevention(false)
        case .preventSaver: await model.changeScreenSaverPrevention(true)
        case .closedEnabled: await model.refresh(); return model.verifiedWork && model.runsWithLidClosed
        case .enableClosed, .disableClosed:
            guard !model.busy else { throw ModeError("Orexin 正忙，请稍后重试。") }
            await model.changeSessionLidMode(self == .enableClosed)
            guard !model.error, model.pending == nil else { throw ModeError(model.message) }
        case .isTrigger: return model.verifiedWork && model.triggerOwnedMode != nil
        case .triggersEnabled: return model.triggers.enabled
        case .enableTriggers: await model.setTriggersEnabled(true)
        case .disableTriggers: await model.setTriggersEnabled(false)
        case .driveEnabled: return model.sessions.driveAlive
        case .enableDrive, .disableDrive:
            model.sessions.driveAlive = self == .enableDrive
            await model.sessions.tick(now: Date())
        case .extend: break
        }
        return model.headline
    }
}
