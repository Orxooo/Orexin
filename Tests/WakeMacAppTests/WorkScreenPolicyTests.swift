// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor final class WorkScreenPolicyTests: XCTestCase {
    private func fixture() -> WorkScreenPolicy {
        WorkScreenPolicy(preferences: UserDefaults(suiteName: "ScreenPolicy." + UUID().uuidString)!)
    }
    private let awake = DisplayState(lidClosed: false, builtInAsleep: false, sessionLocked: false)
    func testMinimumBrightnessKeepsDisplayActiveAndRestoresOriginalBrightness() async throws {
        let policy = fixture(), now = Date()
        var brightness: Float = 0.72, sleeps = 0
        policy.readBrightness = { brightness }; policy.writeBrightness = { brightness = $0 }
        policy.requestSleep = { sleeps += 1 }
        policy.select(.dim, for: .background)
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        XCTAssertEqual(brightness, 0, accuracy: 0.001)
        XCTAssertTrue(policy.behavior(for: .background).keepsDisplayActive)
        XCTAssertEqual(sleeps, 0)
        try policy.restore()
        XCTAssertEqual(brightness, 0.72, accuracy: 0.001)
    }
    func testImmediateSleepIsOneShotAndWakeRestoresSavedPolicy() async {
        let policy = fixture(), now = Date()
        var sleeps = 0
        policy.requestSleep = { sleeps += 1 }
        policy.select(.normalBrightness, for: .background)
        policy.runtimeBehavior = .immediateSleep
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(4))
        XCTAssertEqual(sleeps, 1)
        await policy.tick(mode: .background, working: true, state: DisplayState(lidClosed: true, builtInAsleep: false, sessionLocked: false), onBattery: false, now: now.addingTimeInterval(5))
        XCTAssertEqual(sleeps, 1)
        await policy.tick(mode: .background, working: true, state: DisplayState(lidClosed: true, builtInAsleep: true, sessionLocked: false), onBattery: false, now: now.addingTimeInterval(9))
        XCTAssertEqual(sleeps, 1)
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(10))
        XCTAssertEqual(policy.behavior(for: .background), .normalBrightness)
        XCTAssertNil(policy.runtimeBehavior)
    }
    func testImmediateSleepWakePreservesTriggerOverrideAndFailedRequestRestoresIt() async {
        let policy = fixture(), now = Date()
        policy.select(.normalBrightness, for: .background)
        policy.runtimeBehavior = .systemIdle
        policy.runtimeBehavior = .immediateSleep
        policy.requestSleep = { throw ModeError("Display sleep rejected") }
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        XCTAssertEqual(policy.runtimeBehavior, .systemIdle)
        XCTAssertEqual(policy.background, .normalBrightness)
        XCTAssertTrue(policy.status.contains("Display sleep rejected"))
    }
    func testPresetDefaultsAndLegacyImmediateSleepMigration() {
        let preferences = UserDefaults(suiteName: "ScreenDefaults." + UUID().uuidString)!
        let defaults = WorkScreenPolicy(preferences: preferences)
        XCTAssertEqual(defaults.background, .dim)
        XCTAssertEqual(defaults.desktop, .normalBrightness)
        preferences.set("immediateSleep", forKey: "orexin.screen.background")
        preferences.set("systemIdle", forKey: "orexin.screen.desktop")
        let migrated = WorkScreenPolicy(preferences: preferences)
        XCTAssertEqual(migrated.background, .systemIdle)
        XCTAssertEqual(migrated.desktop, .systemIdle)
    }
    func testDisplayWakeRestoresTriggerOverrideWithoutChangingSavedPreset() async {
        let policy = fixture(), now = Date()
        policy.select(.normalBrightness, for: .background)
        policy.runtimeBehavior = .systemIdle
        policy.runtimeBehavior = .immediateSleep
        policy.readTimeout = { _ in .infinity }
        policy.idleSeconds = { 0 }
        policy.requestSleep = {}
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        await policy.tick(mode: .background, working: true, state: DisplayState(lidClosed: false, builtInAsleep: true, sessionLocked: false), onBattery: false, now: now.addingTimeInterval(1))
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(2))
        XCTAssertEqual(policy.runtimeBehavior, .systemIdle)
        XCTAssertEqual(policy.background, .normalBrightness)
    }
    func testSwitchingFromDimBackgroundToNormalDesktopRestoresOriginalBrightness() async {
        let policy = fixture(), now = Date()
        var brightness: Float = 0.64, sleeps = 0
        policy.readBrightness = { brightness }; policy.writeBrightness = { brightness = $0 }
        policy.requestSleep = { sleeps += 1 }
        policy.select(.dim, for: .background); policy.select(.normalBrightness, for: .desk)
        await policy.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        XCTAssertEqual(brightness, 0, accuracy: 0.001)
        await policy.tick(mode: .desk, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(1))
        XCTAssertEqual(brightness, 0.64, accuracy: 0.001)
        XCTAssertEqual(sleeps, 0)
    }
    func testTimedBackgroundDisplaySleepWaitsForTimeoutEvenWithLidClosed() async {
        let policy = fixture(), now = Date()
        var idle: TimeInterval = 59, sleeps = 0
        policy.readTimeout = { _ in 120 }; policy.idleSeconds = { idle }
        policy.requestSleep = { sleeps += 1 }
        let closed = DisplayState(lidClosed: true, builtInAsleep: false, sessionLocked: false)
        policy.select(.systemIdle, for: .background)
        await policy.tick(mode: .background, working: true, state: closed, onBattery: false, now: now)
        XCTAssertEqual(sleeps, 0)
        idle = 121
        await policy.tick(mode: .background, working: true, state: closed, onBattery: false, now: now.addingTimeInterval(62))
        XCTAssertEqual(sleeps, 1)
    }
    func testIdleSleepReadsDifferentBatteryAndACSettingsAndZeroMeansNever() async {
        let policy = fixture(), now = Date()
        var idle: TimeInterval = 121, sleeps = 0, sources: [Bool] = []
        policy.idleSeconds = { idle }
        policy.readTimeout = { battery in sources.append(battery); return battery ? 120 : .infinity }
        policy.requestSleep = { sleeps += 1 }
        policy.select(.systemIdle, for: .desk)
        await policy.tick(mode: .desk, working: true, state: awake, onBattery: false, now: now)
        XCTAssertEqual(sleeps, 0)
        await policy.tick(mode: .desk, working: true, state: awake, onBattery: true, now: now.addingTimeInterval(1))
        XCTAssertEqual(sleeps, 1); XCTAssertEqual(sources, [false, true])
        idle = 1
        await policy.tick(mode: .desk, working: true, state: awake, onBattery: true, now: now.addingTimeInterval(5))
        XCTAssertEqual(sleeps, 1)
        let text = "Battery Power:\n displaysleep 2\nAC Power:\n displaysleep 0\n"
        XCTAssertEqual(displayTimeoutMinutes(text, onBattery: true), 2)
        XCTAssertEqual(displayTimeoutMinutes(text, onBattery: false), 0)
        XCTAssertNil(displayTimeoutMinutes("not available", onBattery: false))
    }
    func testScreenSleepPoliciesSuspendCursorAndSaverButPreserveDriveChoices() {
        let session = SessionController(preferences: UserDefaults(suiteName: "ScreenEffects." + UUID().uuidString)!)
        session.moveCursor = true; session.driveAlive = true; session.preventScreenSaver = true
        session.screenPolicyPreventsSleep = false
        XCTAssertFalse(session.choices.moveCursor); XCTAssertFalse(session.choices.preventScreenSaver)
        XCTAssertTrue(session.choices.driveAlive)
        session.screenPolicyPreventsSleep = true
        XCTAssertTrue(session.choices.moveCursor); XCTAssertTrue(session.choices.preventDisplaySleep)
        XCTAssertTrue(session.choices.preventScreenSaver)
    }
    func testModeChoicesAndSavedPoliciesRemainIndependent() {
        let policy = fixture()
        XCTAssertEqual(WorkScreenBehavior.choices(for: .background), [.dim, .normalBrightness, .systemIdle])
        XCTAssertEqual(WorkScreenBehavior.choices(for: .desk), [.dim, .normalBrightness, .systemIdle])
        policy.select(.dim, for: .background)
        policy.select(.normalBrightness, for: .desk)
        XCTAssertEqual(policy.behavior(for: .background), .dim)
        XCTAssertEqual(policy.behavior(for: .desk), .normalBrightness)
        policy.select(.immediateSleep, for: .desk)
        XCTAssertEqual(policy.behavior(for: .desk), .normalBrightness)
    }
    func testNormalModeRequestsSleepOnceAtDisplayTimeoutAndRearmsAfterActivity() async {
        let policy = fixture(), now = Date()
        var idle: TimeInterval = 181
        policy.idleSeconds = { idle }; policy.readTimeout = { _ in 180 }
        let first = await policy.normalSleepIsDue(state: awake, onBattery: false, now: now)
        let duplicate = await policy.normalSleepIsDue(state: awake, onBattery: false, now: now.addingTimeInterval(5))
        XCTAssertTrue(first); XCTAssertFalse(duplicate)
        idle = 0
        let active = await policy.normalSleepIsDue(state: awake, onBattery: false, now: now.addingTimeInterval(6))
        XCTAssertFalse(active)
        idle = 181
        let rearmed = await policy.normalSleepIsDue(state: awake, onBattery: false, now: now.addingTimeInterval(10))
        XCTAssertTrue(rearmed)
        let locked = await policy.normalSleepIsDue(state: DisplayState(lidClosed: false, builtInAsleep: true, sessionLocked: true), onBattery: false, now: now.addingTimeInterval(15))
        XCTAssertFalse(locked)
    }
    func testNormalModeStillRequestsSystemSleepWhenDisplayHasAlreadyLocked() async {
        let policy = fixture(), now = Date()
        policy.idleSeconds = { 181 }; policy.readTimeout = { _ in 180 }
        let locked = DisplayState(lidClosed: false, builtInAsleep: true, sessionLocked: true)
        let due = await policy.normalSleepIsDue(state: locked, onBattery: false, now: now)
        XCTAssertTrue(due)
        let repeated = await policy.normalSleepIsDue(state: locked, onBattery: false, now: now.addingTimeInterval(5))
        XCTAssertFalse(repeated)
    }
}
