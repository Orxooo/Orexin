// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor final class ThermalProtectionTests: XCTestCase {
    private func model(_ backend: any ModeBackend = AutomationBackend(), threshold: ThermalThreshold = .heavy) -> AppModel {
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "ThermalProtection." + UUID().uuidString)!,
                             jobLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("wakemac-thermal-test-" + UUID().uuidString))
        model.thermalStateProvider = { .nominal }
        // These regression fixtures exercise the original serious-or-critical policy.
        model.thermalThreshold = threshold
        return model
    }

    func testDefaultThresholdWaitsForCriticalPressure() async {
        let model = model(threshold: .critical)
        XCTAssertTrue(model.thermalReleaseEnabled)
        XCTAssertTrue(model.thermalAudibleAlertEnabled)
        model.thermalStateProvider = { .serious }
        XCTAssertFalse(model.thermalProtectionRequired)
        model.thermalStateProvider = { .critical }
        XCTAssertTrue(model.thermalProtectionRequired)
    }

    func testCriticalDefaultKeepsSeriousWorkAndReleasesAtCritical() async {
        let backend = AutomationBackend(), model = model(backend, threshold: .critical), now = Date()
        await model.sessions.start(now: now)
        let deadline = model.sessions.deadline
        model.thermalStateProvider = { .serious }
        await model.tick(now: now, battery: nil)
        XCTAssertEqual(model.active, .desk)
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.sessions.deadline, deadline)
        model.thermalStateProvider = { .critical }
        await model.tick(now: now.addingTimeInterval(1), battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.sessions.isActive)
        let sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0)
    }

    func testSelectingHeavyImmediatelyReleasesSeriousWork() async {
        let model = model(threshold: .critical)
        await model.choose(.background)
        model.thermalStateProvider = { .serious }
        await model.setThermalThreshold(.heavy)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.keepsAwake)
        XCTAssertFalse(model.runsWithLidClosed)
    }

    func testDisabledReleaseKeepsWorkAndCompletionSleepArmedUntilReenabled() async {
        let backend = AutomationBackend(), model = model(backend), now = Date()
        await model.setThermalReleaseEnabled(false)
        model.thermalStateProvider = { .critical }
        await model.sessions.start(now: now)
        let deadline = model.sessions.deadline
        _ = model.automation.beginJob()
        model.jobRunning = true
        await model.tick(now: now, battery: nil)
        XCTAssertFalse(model.thermalProtectionRequired)
        XCTAssertEqual(model.active, .desk)
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.sessions.deadline, deadline)
        XCTAssertTrue(model.automation.jobArmed)
        await model.setThermalReleaseEnabled(true)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.sessions.isActive)
        XCTAssertFalse(model.automation.jobArmed)
        XCTAssertTrue(model.jobRunning)
        let sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0)
    }

    func testDisablingReleaseDoesNotDiscardFailedCleanupAfterCooling() async {
        let backend = ThermalCleanupBackend(), model = model(backend)
        await model.choose(.background)
        await backend.setRestoreFailure(true)
        model.thermalStateProvider = { .serious }
        await model.tick(battery: nil)
        XCTAssertTrue(model.thermalCleanupPending)
        await model.setThermalReleaseEnabled(false)
        XCTAssertTrue(model.thermalCleanupPending)
        model.thermalStateProvider = { .nominal }
        await backend.setRestoreFailure(false)
        await model.tick(battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.thermalCleanupPending)
        XCTAssertFalse(model.error)
    }

    func testThermalAlertHonorsSoundToggleAndNotifiesOncePerIncident() async {
        for audible in [false, true] {
            let model = model()
            model.setThermalAudibleAlertEnabled(audible)
            var notices: [(String, Bool)] = []
            model.thermalNotificationHandler = { notices.append(($0, $1)) }
            await model.choose(.desk)
            model.thermalStateProvider = { .serious }
            await model.tick(battery: nil)
            await model.tick(battery: nil)
            XCTAssertEqual(notices.count, 1)
            XCTAssertEqual(notices.first?.1, audible)
            XCTAssertTrue(notices.first?.0.contains("温度保护触发") == true)
            model.thermalStateProvider = { .nominal }
            await model.tick(battery: nil)
            await model.choose(.desk)
            model.thermalStateProvider = { .serious }
            await model.tick(battery: nil)
            XCTAssertEqual(notices.count, 2)
        }
    }

    func testThermalAlertStillWorksWhenEmergencyReleaseIsDisabled() async {
        let model = model()
        await model.choose(.desk)
        await model.setThermalReleaseEnabled(false)
        var alerts: [Bool] = []
        model.thermalNotificationHandler = { _, audible in alerts.append(audible) }
        model.thermalStateProvider = { .serious }
        await model.tick(battery: nil)
        await model.tick(battery: nil)
        XCTAssertEqual(alerts, [true])
        XCTAssertEqual(model.active, .desk)
        XCTAssertTrue(model.keepsAwake)
        await model.setThermalReleaseEnabled(true)
        XCTAssertEqual(model.active, .normal)
        XCTAssertEqual(alerts, [true])
    }

    func testThermalPreferencesPersistAndInvalidThresholdUsesCriticalDefault() async {
        let preferences = UserDefaults(suiteName: "ThermalPreferences." + UUID().uuidString)!
        let model = AppModel(backend: AutomationBackend(), preferences: preferences)
        model.thermalStateProvider = { .nominal }
        XCTAssertEqual(model.thermalThreshold, .critical)
        await model.setThermalThreshold(.heavy)
        await model.setThermalReleaseEnabled(false)
        model.setThermalAudibleAlertEnabled(false)
        let restored = AppModel(backend: AutomationBackend(), preferences: preferences)
        XCTAssertEqual(restored.thermalThreshold, .heavy)
        XCTAssertFalse(restored.thermalReleaseEnabled)
        XCTAssertFalse(restored.thermalAudibleAlertEnabled)
        preferences.set("invalid", forKey: "orexin.thermal.threshold")
        XCTAssertEqual(AppModel(backend: AutomationBackend(), preferences: preferences).thermalThreshold, .critical)
    }

    func testSeriousAndCriticalPressureEndTimedWorkWithoutRequestingSleep() async {
        for pressure in [ProcessInfo.ThermalState.serious, .critical] {
            let backend = AutomationBackend(), model = model(backend), now = Date()
            model.sessions.defaultMode = .background
            await model.sessions.start(now: now)
            XCTAssertTrue(model.sessions.isActive)
            model.thermalStateProvider = { pressure }
            await model.tick(now: now, battery: nil)
            XCTAssertEqual(model.active, .normal)
            XCTAssertFalse(model.keepsAwake)
            XCTAssertFalse(model.sessions.isActive)
            XCTAssertNil(model.sessions.deadline)
            let sleeps = await backend.sleeps
            XCTAssertEqual(sleeps, 0)
            XCTAssertTrue(model.history.contains { $0.text.contains("温度") })
        }
    }

    func testFairPressureKeepsCurrentWorkAndDeadline() async {
        let model = model(), now = Date()
        await model.sessions.start(now: now)
        let deadline = model.sessions.deadline
        model.thermalStateProvider = { .fair }
        await model.tick(now: now, battery: nil)
        XCTAssertEqual(model.active, .desk)
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.sessions.deadline, deadline)
    }

    func testHighPressureBlocksManualAndScriptSessionStarts() async {
        let backend = AutomationBackend(), model = model(backend)
        await model.choose(.normal)
        model.thermalStateProvider = { .serious }
        await model.choose(.background)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.keepsAwake)
        await model.sessions.start()
        XCTAssertFalse(model.sessions.isActive)
        let changes = await backend.changes
        XCTAssertEqual(changes, [.normal])
    }

    func testThermalStopDisarmsJobSleepAndKeepsRunningCommandState() async {
        let backend = AutomationBackend(), model = model(backend), now = Date()
        await model.choose(.desk)
        let job = model.automation.beginJob()
        model.jobRunning = true
        model.thermalStateProvider = { .critical }
        await model.tick(now: now, battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertTrue(model.jobRunning)
        XCTAssertFalse(model.automation.jobArmed)
        model.completeJob(id: job, exitCode: 0, at: now)
        XCTAssertNil(model.automation.jobSleepAt)
        let sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0)
    }

    func testOverheatingDuringActivationReleasesNewlyAcquiredWork() async {
        let backend = AutomationBackend(), model = model(backend)
        await model.choose(.normal)
        await backend.holdPower()
        let activation = Task { await model.choose(.background) }
        for _ in 0..<200 {
            if await backend.isWaiting { break }
            await Task.yield()
        }
        let isWaiting = await backend.isWaiting
        XCTAssertTrue(isWaiting)
        model.thermalStateProvider = { .serious }
        await backend.release()
        await activation.value
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.keepsAwake)
    }

    func testRepeatedThermalSamplesNotifyOnceAndCoolingDoesNotRestartSession() async {
        let model = model(), now = Date()
        var notices: [String] = []
        model.notificationHandler = { notices.append($0) }
        await model.sessions.start(now: now)
        model.thermalStateProvider = { .serious }
        await model.tick(now: now, battery: nil)
        await model.tick(now: now.addingTimeInterval(1), battery: nil)
        XCTAssertEqual(notices.filter { $0.contains("温度") }.count, 1)
        model.thermalStateProvider = { .nominal }
        await model.tick(now: now.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.sessions.isActive)
        await model.sessions.start(now: now.addingTimeInterval(7))
        XCTAssertTrue(model.sessions.isActive)
    }

    func testHotCommandStartDoesNotCreateLogOrExecuteCommand() async {
        let backend = AutomationBackend(), model = model(backend)
        await model.choose(.desk)
        model.thermalStateProvider = { .serious }
        await model.startJob(command: "printf should-not-run", directory: "/tmp")
        XCTAssertEqual(model.active, .normal)
        XCTAssertNil(model.jobLogURL)
        XCTAssertFalse(model.jobRunning)
        XCTAssertNil(model.automation.jobID)
    }

    func testFailedThermalCleanupRetriesAfterCoolingBeforeAllowingNewWork() async {
        let backend = ThermalCleanupBackend(), model = model(backend), now = Date()
        await model.choose(.background)
        await backend.setRestoreFailure(true)
        model.thermalStateProvider = { .serious }
        await model.tick(now: now, battery: nil)
        XCTAssertTrue(model.error)
        let stillWorking = await backend.current
        XCTAssertEqual(stillWorking, .background)
        model.thermalStateProvider = { .nominal }
        await backend.setRestoreFailure(false)
        await model.tick(now: now.addingTimeInterval(1), battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.keepsAwake)
        XCTAssertFalse(model.error)
    }

    func testHeatArrivingDuringAutomaticSleepCleanupCancelsSleepRequest() async {
        let backend = AutomationBackend(), model = model(backend), now = Date()
        await model.choose(.desk)
        let job = model.automation.beginJob()
        model.completeJob(id: job, exitCode: 0, at: now.addingTimeInterval(-61))
        await backend.holdPower()
        let countdown = Task { await model.tick(now: now, battery: nil) }
        for _ in 0..<200 {
            if await backend.isWaiting { break }
            await Task.yield()
        }
        let isWaiting = await backend.isWaiting
        XCTAssertTrue(isWaiting)
        model.thermalStateProvider = { .serious }
        await backend.release()
        await countdown.value
        let sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0)
        XCTAssertEqual(model.active, .normal)
        XCTAssertNil(model.automation.jobSleepAt)
    }

    func testObservedHeatDuringActivationStillStopsWorkAfterCooling() async {
        let backend = AutomationBackend(), model = model(backend), now = Date()
        await model.choose(.normal)
        await backend.holdPower()
        let activation = Task { await model.choose(.background) }
        for _ in 0..<200 {
            if await backend.isWaiting { break }
            await Task.yield()
        }
        let isWaiting = await backend.isWaiting
        XCTAssertTrue(isWaiting)
        model.thermalStateProvider = { .serious }
        await model.tick(now: now, battery: nil)
        model.thermalStateProvider = { .nominal }
        await backend.release()
        await activation.value
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.keepsAwake)
        XCTAssertNil(model.automation.jobSleepAt)
    }

    func testUnverifiedActivationAndFailedRollbackKeepThermalCleanupArmed() async {
        let backend = ThermalCleanupBackend(), model = model(backend), now = Date()
        await model.choose(.normal)
        await backend.armActivationFailure()
        let activation = Task { await model.choose(.background) }
        for _ in 0..<200 {
            if await backend.isWaiting { break }
            await Task.yield()
        }
        let isWaiting = await backend.isWaiting
        XCTAssertTrue(isWaiting)
        model.thermalStateProvider = { .serious }
        await backend.release()
        await activation.value
        let retained = await backend.current
        XCTAssertEqual(retained, .background)
        XCTAssertTrue(model.error)
        model.thermalStateProvider = { .nominal }
        await backend.setRestoreFailure(false)
        await model.tick(now: now, battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertFalse(model.keepsAwake)
    }

    func testThermalLockPolicyHandoffWaitsWithoutRepeatedSettingsRequests() async {
        let backend = ThermalCleanupBackend(), model = model(backend), now = Date()
        await model.choose(.background)
        await backend.setLock(.off)
        model.thermalStateProvider = { .serious }
        await model.tick(now: now, battery: nil)
        XCTAssertEqual(model.pending, .normal)
        await model.tick(now: now.addingTimeInterval(1), battery: nil)
        let requests = await backend.lockRequests
        XCTAssertEqual(requests, 1)
        model.thermalStateProvider = { .nominal }
        await backend.setLock(.immediate)
        await model.refresh()
        await model.tick(now: now.addingTimeInterval(2), battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertNil(model.pending)
    }

    func testProtectedTicksRetryRetainedDisplayEffectAfterNormalCleanup() async {
        let effects = RetainedThermalEffects(), now = Date()
        let model = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "ThermalEffects." + UUID().uuidString)!, sessionEffects: effects)
        model.thermalThreshold = .heavy
        model.thermalStateProvider = { .nominal }
        model.sessions.preventDisplaySleep = true
        await model.choose(.desk)
        await model.sessions.tick(now: now)
        XCTAssertTrue(effects.displayHeld)
        effects.failNextRelease = true
        model.thermalStateProvider = { .serious }
        await model.tick(now: now, battery: nil)
        XCTAssertEqual(model.active, .normal)
        XCTAssertTrue(effects.displayHeld)
        await model.tick(now: now.addingTimeInterval(1), battery: nil)
        XCTAssertFalse(effects.displayHeld)
    }
}

private actor ThermalCleanupBackend: ModeBackend {
    var current: WorkMode = .normal
    var lockRequests = 0
    private var lockPolicy: LockPolicy = .immediate
    private var restoreFailure = false
    private var failActivation = false
    private var gate: CheckedContinuation<Void, Never>?
    func setRestoreFailure(_ value: Bool) { restoreFailure = value }
    func setLock(_ value: LockPolicy) { lockPolicy = value }
    func armActivationFailure() { failActivation = true }
    var isWaiting: Bool { gate != nil }
    func release() { gate?.resume(); gate = nil }
    func snapshot() -> Snapshot {
        Snapshot(sleepDisabled: current == .background, lockPolicy: lockPolicy,
                 idleSleepPrevented: current != .normal, displaySleepAllowed: true,
                 backgroundLeaseActive: current == .background)
    }
    func configurePower(_ mode: WorkMode) async throws {
        if mode == .normal && restoreFailure { throw ModeError("Test cleanup unavailable") }
        current = mode
        if mode == .background && failActivation {
            await withCheckedContinuation { gate = $0 }
            restoreFailure = true
            throw ModeError("Test activation readback unavailable")
        }
    }
    func requestLockPolicy(_ policy: LockPolicy) { lockRequests += 1 }
    func sleepNow() {}
}

@MainActor private final class RetainedThermalEffects: SessionEffectManaging {
    var displayHeld = false
    var failNextRelease = false
    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
        displayHeld = working && choices.preventDisplaySleep
        return SessionEffectReport()
    }
    func release() {
        if failNextRelease { failNextRelease = false; return }
        displayHeld = false
    }
}
