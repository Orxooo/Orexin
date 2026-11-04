// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor final class AwakeModeTests: XCTestCase {
    private func preferences() -> UserDefaults { UserDefaults(suiteName: "UnifiedAwake." + UUID().uuidString)! }
    func testNewManualAwakeModeStartsAtNormalBrightnessAfterPreviousDimSelection() async {
        let model = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
        model.thermalStateProvider = { .nominal }
        await model.choose(.normal)
        model.workScreen.select(.dim, for: .desk)
        await model.selectWorkPreset(.desk)
        XCTAssertTrue(model.verifiedWork)
        XCTAssertEqual(model.workScreen.behavior(for: .desk), .normalBrightness)
        await model.setWorkScreenBehavior(.dim)
        XCTAssertEqual(model.workScreen.behavior(for: .desk), .dim)
        await model.choose(.normal)
        await model.setKeepsAwake(true)
        XCTAssertTrue(model.verifiedWork)
        XCTAssertEqual(model.workScreen.behavior(for: model.active ?? .desk), .normalBrightness)
        await model.choose(.normal)
    }
    func testNewTimedSessionStartsAtNormalBrightnessAfterPreviousDimSelection() async {
        let model = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
        model.thermalStateProvider = { .nominal }
        await model.choose(.normal)
        model.workScreen.select(.dim, for: .desk)
        model.sessions.endCondition = .indefinite
        await model.sessions.start()
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.workScreen.behavior(for: model.active ?? .desk), .normalBrightness)
        await model.sessions.end()
    }
    func testStartingTimedSessionPreservesDimChoiceDuringActiveWork() async {
        let model = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
        model.thermalStateProvider = { .nominal }
        await model.selectWorkPreset(.desk)
        await model.setWorkScreenBehavior(.dim)
        model.sessions.endCondition = .indefinite
        await model.sessions.start()
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.workScreen.behavior(for: .desk), .dim)
        await model.sessions.end()
    }
    func testNewManualAwakeModeRequestsNormalBrightnessThroughService() async throws {
        let prefs = preferences()
        let service = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: VerifiedAwakeEffects())
        service.isTaskService = true; service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        service.thermalStateProvider = { .nominal }
        await service.choose(.normal)
        let path = "/tmp/orx-default-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: VerifiedAwakeEffects())
        client.serviceSocket = path
        client.workScreen.select(.dim, for: .desk)
        await client.selectWorkPreset(.desk)
        XCTAssertTrue(client.verifiedWork)
        XCTAssertEqual(service.workRequests.active.first?.spec.screen, .awake)
        XCTAssertEqual(service.workScreen.behavior(for: .desk), .normalBrightness)
        await client.choose(.normal)
    }
    func testDisplayWakeMakesNormalBrightnessTheInterfaceRequest() async throws {
        let prefs = preferences()
        let service = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: VerifiedAwakeEffects())
        service.isTaskService = true; service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        service.thermalStateProvider = { .nominal }
        let screen = WorkScreenPolicy(preferences: prefs, monitorKeyboard: false)
        var brightness: Float = 0.7
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestSleep = { XCTFail("The test must not sleep the real display") }
        service.workScreen = screen
        await service.choose(.normal)
        let path = "/tmp/orx-wake-default-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: VerifiedAwakeEffects())
        client.serviceSocket = path
        await client.selectWorkPreset(.desk)
        await client.setWorkScreenBehavior(.dim)
        XCTAssertEqual(service.workRequests.active.first?.spec.screen, .dim)
        let awake = DisplayState(lidClosed: false, builtInAsleep: false, sessionLocked: false)
        await screen.tick(mode: .desk, working: true, state: awake, onBattery: false, now: Date())
        screen.resumeAfterDisplayWake()
        await screen.tick(mode: .desk, working: true, state: awake, onBattery: false, now: Date())
        XCTAssertTrue(screen.dimmingPaused)
        client.adoptServiceReply(service.taskControlReply())
        await client.applyWorkScreenPolicy(now: Date())
        XCTAssertEqual(service.workRequests.active.count, 1)
        XCTAssertEqual(service.workRequests.active.first?.spec.screen, .awake)
        XCTAssertEqual(client.workScreen.ownBehavior(for: .desk), .normalBrightness)
        XCTAssertTrue(client.verifiedWork)
        await client.setWorkScreenBehavior(.dim)
        XCTAssertEqual(service.workRequests.active.first?.spec.screen, .dim)
        XCTAssertFalse(screen.dimmingPaused)
        await client.choose(.normal)
    }
    func testScriptAwakeArgumentsSeparateClamshellChoice() throws {
        XCTAssertEqual(try ScriptSessionArguments([:]).mode, .desk)
        XCTAssertEqual(try ScriptSessionArguments(["mode": "awake", "clamshell": true]).mode, .background)
        XCTAssertEqual(try ScriptSessionArguments(["mode": "awake", "clamshell": false]).mode, .desk)
        XCTAssertThrowsError(try ScriptSessionArguments(["mode": "unknown"]))
    }
    func testIdleClamshellOptionShowsSavedChoiceWithoutStartingWork() async {
        let m = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
        m.thermalStateProvider = { .nominal }
        await m.choose(.normal)
        m.sessions.defaultMode = .background
        XCTAssertTrue(m.clamshellOptionEnabled)
        await m.setClamshellOption(false)
        XCTAssertEqual(m.preferredAwakeMode, .desk)
        XCTAssertEqual(m.active, .normal)
        await m.setClamshellOption(true)
        XCTAssertTrue(m.clamshellOptionEnabled)
        XCTAssertEqual(m.active, .normal)
    }
    func testClamshellChangesKeepActiveDisplayAndScreenSaverOverrides() async {
        let m = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
        m.thermalStateProvider = { .nominal }
        m.workScreen.readTimeout = { _ in .infinity }
        m.workScreen.select(.systemIdle, for: .desk)
        await m.choose(.desk)
        await m.changeScreenSaverPrevention(true)
        XCTAssertTrue(m.sessions.effectivePreventScreenSaver)
        for enabled in [true, false] {
            await m.changeSessionLidMode(enabled)
            XCTAssertEqual(m.active, enabled ? .background : .desk)
            XCTAssertEqual(m.workScreen.behavior(for: m.active ?? .desk), .normalBrightness)
            XCTAssertTrue(m.sessions.effectivePreventScreenSaver)
            XCTAssertTrue(m.sessions.effectReport.screenSaverAssertionActive)
        }
        await m.choose(.normal)
    }
    func testServiceClamshellChangePreservesActiveScreenSaverChoice() async throws {
        let prefs = preferences()
        let service = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: VerifiedAwakeEffects())
        service.isTaskService = true; service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        service.thermalStateProvider = { .nominal }
        service.workScreen.readTimeout = { _ in .infinity }
        await service.choose(.normal)
        let path = "/tmp/orx-awake-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: VerifiedAwakeEffects())
        client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.choose(.desk)
        await client.changeScreenSaverPrevention(true)
        XCTAssertTrue(service.sessions.effectReport.screenSaverAssertionActive)
        await client.setClamshellOption(true)
        XCTAssertEqual(service.active, .background)
        XCTAssertTrue(service.sessions.effectReport.screenSaverAssertionActive)
        XCTAssertEqual(service.workScreen.behavior(for: .background), .normalBrightness)
        XCTAssertEqual(service.workRequests.active.count, 1)
        await client.choose(.normal)
    }
    func testMigrationUsesThePreviouslySelectedSessionsScreenPolicy() {
        let prefs = preferences()
        prefs.set("background", forKey: "orexin.session.defaultMode")
        prefs.set("systemIdle", forKey: "orexin.screen.background")
        prefs.set("dim", forKey: "orexin.screen.desktop")
        let screen = WorkScreenPolicy(preferences: prefs, monitorKeyboard: false)
        XCTAssertEqual(screen.ownBehavior(for: .background), .systemIdle)
        XCTAssertEqual(screen.ownBehavior(for: .desk), .systemIdle)
    }
    func testImmediateDisplaySleepHonorsIndependentTaskRequirements() async throws {
        for needsDisplay in [true, false] {
            let m = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
            m.thermalStateProvider = { .nominal }
            m.workScreen.readTimeout = { _ in .infinity }
            var sleeps = 0
            m.workScreen.requestSleep = { sleeps += 1 }
            await m.choose(.normal)
            let handle = try await m.registerWork(.init(title: "independent", screen: needsDisplay ? .awake : .idle))
            await m.sleepDisplayNow()
            if needsDisplay {
                XCTAssertEqual(sleeps, 0)
                m.isTaskService = true
                let reply = await m.handleTaskControl(.init("display-sleep"))
                XCTAssertFalse(reply.ok)
            }
            XCTAssertEqual(m.workScreen.behavior(for: .desk), needsDisplay ? .normalBrightness : .immediateSleep)
            XCTAssertTrue(m.requestSatisfied(m.workRequests.active.first { $0.id == handle.id }!.spec))
            await m.choose(.normal)
        }
    }
    func testScreenSaverRequestImpliesAnAwakeDisplay() throws {
        var ledger = WorkRequestLedger()
        let spec = WorkRequestSpec(title: "saver prevention", screen: .idle, preventScreenSaver: true)
        let handle = try ledger.register(spec, now: Date())
        XCTAssertEqual(ledger.demand?.screen, .awake)
        XCTAssertEqual(ledger.demand?.preventScreenSaver, true)
        _ = try ledger.register(spec, handle: handle, now: Date())
        XCTAssertEqual(ledger.active.count, 1)
    }
    func testNonImmediatePasswordPolicySuspendsIdleLock() async {
        let idle = IdlePolicyController(preferences: preferences())
        idle.lockEnabled = true; idle.screenSaverEnabled = false
        idle.workingProvider = { true }; idle.unlockedProvider = { true }
        idle.immediateAuthentication = { false }; idle.idleProvider = { 3600 }
        var locks = 0
        idle.lockAction = { locks += 1 }
        await idle.tick()
        XCTAssertEqual(locks, 0)
        XCTAssertEqual(idle.status, "当前密码策略不执行闲置锁定。")
    }
    func testIndependentTaskKeepsConflictingScreenAndSaverChoicesUnchanged() async throws {
        let m = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: VerifiedAwakeEffects())
        m.thermalStateProvider = { .nominal }
        m.workScreen.readTimeout = { _ in .infinity }
        await m.choose(.desk)
        let handle = try await m.registerWork(.init(title: "screen automation", screen: .awake))
        await m.setWorkScreenBehavior(.dim)
        XCTAssertEqual(m.workScreen.desktop, .normalBrightness)
        await m.changeDisplayPrevention(false)
        XCTAssertEqual(m.workScreen.ownBehavior(for: .desk), .normalBrightness)
        await m.changeScreenSaverPrevention(false)
        XCTAssertNil(m.sessions.effectOverrides?.saver)
        XCTAssertTrue(m.sessions.effectivePreventScreenSaver)
        try await m.completeWork(handle, exitCode: 0)
        await m.changeScreenSaverPrevention(false)
        XCTAssertEqual(m.sessions.effectOverrides?.saver, false)
        await m.setWorkScreenBehavior(.systemIdle)
        XCTAssertEqual(m.workScreen.desktop, .systemIdle)
        await m.choose(.normal)
    }
    func testClamshellPoliciesShareOneScreenSelection() {
        let screen = WorkScreenPolicy(preferences: preferences(), monitorKeyboard: false)
        screen.select(.dim, for: .desk)
        XCTAssertEqual(screen.ownBehavior(for: .background), .dim)
        screen.select(.systemIdle, for: .background)
        XCTAssertEqual(screen.ownBehavior(for: .desk), .systemIdle)
    }
    func testUnifiedScreenSettingPersistsForBothPowerPolicies() {
        let prefs = preferences()
        let screen = WorkScreenPolicy(preferences: prefs, monitorKeyboard: false)
        screen.select(.dim, for: .background)
        let restored = WorkScreenPolicy(preferences: prefs, monitorKeyboard: false)
        XCTAssertEqual(restored.ownBehavior(for: .desk), .dim)
        XCTAssertEqual(restored.ownBehavior(for: .background), .dim)
    }
    func testKeepAwakeRespectsSavedClamshellChoice() async {
        let m = AppModel(backend: AutomationBackend(), preferences: preferences())
        m.thermalStateProvider = { .nominal }
        m.sessions.defaultMode = .background
        await m.setKeepsAwake(true)
        XCTAssertEqual(m.active, .background)
        await m.setKeepsAwake(false)
        XCTAssertEqual(m.active, .normal)
    }
    func testScreenDependentEffectsPauseWhenDisplaySleepIsAllowed() {
        let session = SessionController(preferences: preferences())
        session.driveAlive = true; session.moveCursor = true; session.preventScreenSaver = true
        session.screenPolicyPreventsSleep = false
        XCTAssertFalse(session.choices.moveCursor)
        XCTAssertFalse(session.choices.preventScreenSaver)
        XCTAssertTrue(session.choices.driveAlive)
    }
    func testUnlockedOptionRequiresPasswordPolicyReadback() {
        let prefs = preferences()
        prefs.set(true, forKey: "orexin.work.keepUnlocked")
        let m = AppModel(backend: AutomationBackend(), preferences: prefs)
        m.active = .desk
        m.snapshot = Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: true, displaySleepAllowed: true, backgroundLeaseActive: false)
        XCTAssertFalse(m.verifiedWork)
        m.snapshot?.lockPolicy = .off
        XCTAssertTrue(m.verifiedWork)
    }
    func testScreenSaverRequirementNeedsAnActiveAssertion() async {
        let m = AppModel(backend: AutomationBackend(), preferences: preferences(), sessionEffects: ScreenOnlyEffects())
        m.thermalStateProvider = { .nominal }
        await m.choose(.desk)
        XCTAssertFalse(m.requestSatisfied(.init(title: "interactive", screen: .awake, preventScreenSaver: true)))
        XCTAssertTrue(m.requestSatisfied(.init(title: "display only", screen: .awake, preventScreenSaver: false)))
        await m.choose(.normal)
    }

}

@MainActor private final class ScreenOnlyEffects: SessionEffectManaging {
    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
        .init(displayAssertionActive: working && choices.preventDisplaySleep)
    }
    func release() {}
}

@MainActor final class VerifiedAwakeEffects: SessionEffectManaging {
    func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
        .init(displayAssertionActive: working && choices.preventDisplaySleep, screenSaverAssertionActive: working && choices.preventScreenSaver)
    }
    func release() {}
}
