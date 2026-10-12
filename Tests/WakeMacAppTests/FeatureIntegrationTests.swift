// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor private final class IntegrationObservations: TriggerObservationSource {
    var connected = true
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
        var snapshot = TriggerSnapshot(); snapshot.externalDisplay = connected; return snapshot
    }
}
@MainActor final class FeatureIntegrationTests: XCTestCase {
    func testQueuedBatterySleepStillChecksPowerBeforeSleeping() async {
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "QueuedBattery." + UUID().uuidString)!)
        model.battery = BatteryReading(percent: 10, onBattery: true)
        await backend.holdPower()
        let start = Task { await model.choose(.desk) }
        while await !backend.isWaiting { await Task.yield() }
        await model.choose(.normal, sleep: true, automatic: true, batterySleep: true)
        model.battery = BatteryReading(percent: 10, onBattery: false)
        await backend.release(); await start.value
        let sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0)
    }
    func testAutomaticSleepDuringModeTransitionIsAppliedAfterTheTransition() async {
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "QueuedEnd." + UUID().uuidString)!)
        await backend.holdPower()
        let start = Task { await model.choose(.desk) }
        while await !backend.isWaiting { await Task.yield() }
        await model.choose(.normal, sleep: true, automatic: true)
        await backend.release()
        await start.value
        let sleeps = await backend.sleeps, current = await backend.current
        XCTAssertEqual(current, .normal); XCTAssertEqual(sleeps, 1)
    }
    func testSessionConditionRestoresNormalBeforeSleepingInEitherWorkMode() async {
        for mode in [WorkMode.desk, .background] {
            let backend = AutomationBackend()
            let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "ConditionEnd." + UUID().uuidString)!)
            let date = Date()
            model.sessions.defaultMode = mode
            model.sessions.endCondition = .duration; model.sessions.durationMinutes = 1
            await model.sessions.start(now: date)
            XCTAssertEqual(model.active, mode)
            await model.sessions.tick(now: date.addingTimeInterval(61))
            let sleeps = await backend.sleeps, current = await backend.current
            XCTAssertEqual(current, .normal); XCTAssertEqual(sleeps, 1)
            await model.sessions.tick(now: date.addingTimeInterval(70))
            let finalSleeps = await backend.sleeps
            XCTAssertEqual(finalSleeps, 1)
        }
    }
    func testManualSessionEndRestoresNormalWithoutForcingSleep() async {
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "ManualEnd." + UUID().uuidString)!)
        await model.sessions.start(now: Date())
        await model.sessions.end()
        let sleeps = await backend.sleeps, current = await backend.current
        XCTAssertEqual(current, .normal); XCTAssertEqual(sleeps, 0)
    }
    private func fixture() -> (AppModel, IntegrationObservations) {
        let observation = IntegrationObservations()
        let model = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "IntegrationTests." + UUID().uuidString)!, triggerSource: observation)
        model.triggers.save(TriggerRule(name: "Display", enabled: true, conditions: [TriggerCondition(kind: .externalDisplay)]))
        return (model, observation)
    }
    func testEnabledRuleActivatesAfterStartupRecoveryThenRestoresWhenConditionClears() async {
        let (model, observation) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        XCTAssertEqual(model.active, .desk)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .normal)
    }
    func testManualNormalSuppressesMatchingRuleUntilItClearsAndMatchesAgain() async {
        let (model, observation) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        await model.choose(.normal)
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .normal)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(12), battery: nil)
        observation.connected = true
        await model.tickFeatures(now: date.addingTimeInterval(18), battery: nil)
        XCTAssertEqual(model.active, .desk)
    }
    func testTimedSessionTakesPriorityAndCompletionCannotImmediatelyRetriggerWork() async {
        let (model, _) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        model.sessions.endCondition = .duration; model.sessions.durationMinutes = 1
        await model.sessions.start(now: date)
        await model.tickFeatures(now: date.addingTimeInterval(5), battery: nil)
        XCTAssertTrue(model.sessions.isActive)
        await model.tickFeatures(now: date.addingTimeInterval(61), battery: nil)
        XCTAssertEqual(model.active, .normal); XCTAssertFalse(model.sessions.isActive)
        await model.tickFeatures(now: date.addingTimeInterval(70), battery: nil)
        XCTAssertEqual(model.active, .normal)
    }
    func testChangedLockPolicyReleasesManualWorkDuringRefresh() async {
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "LockRefresh." + UUID().uuidString)!)
        await model.choose(.desk); await backend.removeLock(); await model.refresh()
        let current = await backend.current
        XCTAssertEqual(current, .normal); XCTAssertEqual(model.pending, .normal)
        XCTAssertFalse(model.keepsAwake)
    }
    func testScriptArgumentsRejectValuesOutsideSessionLimitsBeforeChangingState() throws {
        XCTAssertEqual(try ScriptSessionArguments(["minutes": NSNumber(value: 10080)]).minutes, 10080)
        XCTAssertThrowsError(try ScriptSessionArguments(["minutes": NSNumber(value: 10081)]))
        XCTAssertThrowsError(try ScriptSessionArguments(["minutes": NSNumber(value: 0.5)]))
        XCTAssertThrowsError(try ScriptSessionArguments(["mode": "normal"]))
    }
    func testTriggerRuntimeOverridesAndQuickChangesResetOnRuleExit() async {
        let (model, observation) = fixture(), date = Date()
        var rule = model.triggers.rules[0]; rule.preventDisplaySleep = true; rule.preventScreenSaver = true; model.triggers.save(rule)
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        XCTAssertTrue(model.sessions.effectivePreventDisplaySleep); XCTAssertTrue(model.sessions.effectivePreventScreenSaver)
        XCTAssertFalse(model.sessions.preventDisplaySleep); XCTAssertFalse(model.sessions.preventScreenSaver)
        await model.changeDisplayPrevention(false)
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertFalse(model.sessions.effectivePreventDisplaySleep)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(12), battery: nil)
        XCTAssertNil(model.sessions.effectOverrides)
        observation.connected = true
        await model.tickFeatures(now: date.addingTimeInterval(18), battery: nil)
        XCTAssertTrue(model.sessions.effectivePreventDisplaySleep)
        await model.choose(.normal)
    }
    func testTriggerMasterDisableEndsOnlyTriggerOwnedWork() async {
        let (model, _) = fixture(), date = Date()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        await model.setTriggersEnabled(false)
        XCTAssertEqual(model.active, .normal); XCTAssertNil(model.sessions.effectOverrides)
        await model.choose(.desk)
        await model.setTriggersEnabled(false)
        XCTAssertEqual(model.active, .desk)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationPreservesManualBackgroundWork() async {
        let (model, _) = fixture()
        await model.choose(.background)
        await model.handleSystemWillSleep()
        XCTAssertEqual(model.active, .background)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationPreservesTimedBackgroundDeadline() async {
        let (model, _) = fixture()
        model.sessions.defaultMode = .background
        model.sessions.endCondition = .duration
        await model.sessions.start()
        let deadline = model.sessions.deadline
        await model.handleSystemWillSleep()
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.sessions.deadline, deadline)
        XCTAssertEqual(model.active, .background)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationEndsDeskSession() async {
        let (model, _) = fixture()
        await model.sessions.start()
        await model.handleSystemWillSleep()
        XCTAssertFalse(model.sessions.isActive)
        XCTAssertEqual(model.active, .normal)
    }
    func testTransientPowerReadbackPreservesOwnedBackgroundDeadline() async {
        let (model, _) = fixture()
        model.sessions.defaultMode = .background; model.sessions.endCondition = .duration
        await model.sessions.start(); let deadline = model.sessions.deadline
        model.active = nil
        model.snapshot = Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: true,
                                  displaySleepAllowed: true, backgroundLeaseActive: true)
        await model.handleSystemWillSleep()
        XCTAssertTrue(model.sessions.isActive); XCTAssertEqual(model.sessions.deadline, deadline)
        await model.choose(.normal)
    }
    func testSystemSleepNotificationPreservesRuleOwnedDeskWork() async {
        let (model, _) = fixture()
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: Date(), battery: nil)
        await model.handleSystemWillSleep()
        XCTAssertEqual(model.active, .desk)
        await model.choose(.normal)
    }

    func testThermalStopSuppressesRuleUntilItsConditionClearsAfterCooling() async {
        let (model, observation) = fixture(), date = Date()
        var pressure = ProcessInfo.ThermalState.nominal
        model.thermalStateProvider = { pressure }
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: date, battery: nil)
        XCTAssertEqual(model.active, .desk)
        // The supplied thermal panel now defaults to CRITICAL; HEAVY remains
        // covered by the explicitly configured thermal regression fixtures.
        pressure = .critical
        await model.tickFeatures(now: date.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .normal)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(12), battery: nil)
        observation.connected = true
        await model.tickFeatures(now: date.addingTimeInterval(18), battery: nil)
        XCTAssertEqual(model.active, .normal)
        pressure = .nominal
        await model.tickFeatures(now: date.addingTimeInterval(24), battery: nil)
        XCTAssertEqual(model.active, .normal)
        observation.connected = false
        await model.tickFeatures(now: date.addingTimeInterval(30), battery: nil)
        observation.connected = true
        await model.tickFeatures(now: date.addingTimeInterval(36), battery: nil)
        XCTAssertEqual(model.active, .desk)
    }
}
