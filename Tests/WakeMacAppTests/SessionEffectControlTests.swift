// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
import AppKit
import SwiftUI
@testable import WakeMac
import WakeMacCore

@MainActor final class SessionEffectControlTests: XCTestCase {
    private final class Observations: TriggerObservationSource {
        var connected = true
        func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
            var snapshot = TriggerSnapshot(); snapshot.acConnected = connected; snapshot.externalDisplay = !connected; return snapshot
        }
    }
    private final class Effects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
            .init(displayAssertionActive: choices.preventDisplaySleep,
                  display: choices.preventDisplaySleep ? "display.active" : "允许显示器休眠",
                  screenSaver: choices.preventScreenSaver ? "saver.active" : "允许屏保",
                  cursor: choices.moveCursor ? "cursor.active" : "未启用")
        }
        func release() {}
    }
    private func model() -> AppModel {
        AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "EffectControls." + UUID().uuidString)!, sessionEffects: Effects())
    }
    func testScreenSaverCanBeTurnedOffWhileDisplayStaysAwake() async {
        let m = model()
        await m.choose(.desk)
        await m.changeScreenSaverPrevention(false)
        XCTAssertTrue(m.sessions.effectivePreventDisplaySleep)
        XCTAssertFalse(m.sessions.effectivePreventScreenSaver)
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        await m.applyWorkScreenPolicy(now: Date().addingTimeInterval(6))
        XCTAssertFalse(m.sessions.effectivePreventScreenSaver)
        await m.choose(.normal)
    }
    func testFreshDefaultsShowTheScreenChoicesThatStartingWorkWillUse() async {
        let m = model()
        XCTAssertTrue(m.workScreen.desktop.keepsDisplayActive)
        XCTAssertTrue(m.sessions.effectivePreventDisplaySleep)
        XCTAssertTrue(m.sessions.effectivePreventScreenSaver)
        await m.sessions.start()
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        await m.sessions.end()
    }
    func testStoredSaverChoiceIsPreviewedWithTheSelectedModePreset() async {
        let prefs = UserDefaults(suiteName: "ScreenPreview." + UUID().uuidString)!
        prefs.set("background", forKey: "orexin.session.defaultMode")
        prefs.set(false, forKey: "orexin.session.preventDisplaySleep")
        prefs.set(false, forKey: "orexin.session.preventScreenSaver")
        let m = AppModel(backend: AutomationBackend(), preferences: prefs, sessionEffects: Effects())
        XCTAssertTrue(m.workScreen.background.keepsDisplayActive)
        XCTAssertTrue(m.sessions.effectivePreventDisplaySleep)
        XCTAssertFalse(m.sessions.effectivePreventScreenSaver)
        await m.sessions.start()
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        await m.sessions.end()
    }
    func testEnablingScreenSaverPreventionSelectsACompatibleDisplayPolicy() async {
        let m = model()
        m.workScreen.select(.systemIdle, for: .desk)
        await m.choose(.desk)
        await m.changeScreenSaverPrevention(true)
        XCTAssertEqual(m.workScreen.behavior(for: .desk), .normalBrightness)
        XCTAssertTrue(m.sessions.effectivePreventScreenSaver)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testAllowingDisplaySleepSuspendsScreenSaverPrevention() async {
        let m = model()
        await m.choose(.desk)
        await m.changeScreenSaverPrevention(true)
        await m.changeDisplayPrevention(false)
        XCTAssertFalse(m.sessions.effectivePreventDisplaySleep)
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testExplicitScreenPolicyReplacesThePreviousDisplayOverride() async {
        let m = model()
        await m.choose(.desk)
        await m.changeDisplayPrevention(false)
        await m.setWorkScreenBehavior(.normalBrightness)
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        XCTAssertFalse(m.sessions.effectReport.display.contains("其他工作任务"))
        await m.choose(.normal)
    }
    func testRuleScreenSaverPreventionSelectsCompatiblePolicyWhenDisplayIsInherited() async {
        let m = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "RuleEffects." + UUID().uuidString)!,
                         triggerSource: Observations(), sessionEffects: Effects())
        m.workScreen.select(.systemIdle, for: .desk)
        m.triggers.enabled = true
        let rule = TriggerRule(name: "Power", enabled: true, conditions: [.init(kind: .acConnected)], preventScreenSaver: true)
        XCTAssertNil(m.triggers.save(rule))
        await m.choose(.normal, automatic: true, startupRecovery: true)
        await m.tickFeatures(now: Date(), battery: nil)
        XCTAssertEqual(m.workScreen.behavior(for: .desk), .normalBrightness)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testCursorExplainsScreenPolicySuspensionAndInactiveWork() async {
        let m = model()
        m.sessions.moveCursor = true
        await m.sessions.tick(now: Date())
        XCTAssertTrue(m.sessions.effectReport.cursor.contains("工作模式"))
        m.workScreen.select(.systemIdle, for: .desk)
        await m.choose(.desk)
        await m.applyWorkScreenPolicy(now: Date())
        XCTAssertTrue(m.sessions.effectReport.cursor.contains("屏幕策略"))
        XCTAssertTrue(m.sessions.moveCursor)
        XCTAssertFalse(m.sessions.choices.moveCursor)
        await m.choose(.normal)
    }
    func testPermissionRefreshNeverRequestsAccessOrOpensSettings() {
        let m = model(), session = m.sessions
        var requests = 0, openings = 0
        session.cursorAccessCheck = { false }
        session.cursorAccessRequest = { requests += 1; return false }
        session.cursorAccessSettings = { openings += 1; return true }
        session.refreshCursorAccess()
        XCTAssertFalse(session.cursorAccessGranted)
        XCTAssertEqual(requests, 0); XCTAssertEqual(openings, 0)
        session.requestCursorAccess()
        XCTAssertEqual(requests, 1); XCTAssertEqual(openings, 1)
        XCTAssertTrue(session.cursorAccessStatus.contains("已打开"))
        session.cursorAccessCheck = { true }
        session.refreshCursorAccess()
        XCTAssertTrue(session.cursorAccessGranted)
        XCTAssertEqual(session.cursorAccessStatus, "辅助功能已授权")
        session.requestCursorAccess()
        XCTAssertEqual(requests, 1); XCTAssertEqual(openings, 1)
    }
    func testPermissionSettingsFailureIsActionable() {
        let m = model(), session = m.sessions
        session.cursorAccessCheck = { false }
        session.cursorAccessRequest = { false }
        session.cursorAccessSettings = { false }
        session.requestCursorAccess()
        XCTAssertFalse(session.cursorAccessGranted)
        XCTAssertTrue(session.cursorAccessStatus.contains("无法打开"))
        XCTAssertTrue(session.cursorAccessStatus.contains("系统设置"))
    }
    func testPreconfiguredScreenSaverChoicesSurviveEnteringWork() async {
        let m = model()
        m.workScreen.select(.systemIdle, for: .desk)
        m.workScreen.select(.systemIdle, for: .background)
        await m.choose(.normal)
        await m.changeScreenSaverPrevention(true)
        await m.choose(.desk)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        await m.choose(.background)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
        await m.changeScreenSaverPrevention(false)
        await m.choose(.desk)
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testServiceBackedScreenSaverOffReachesTheAssertionOwner() async throws {
        let service = model()
        service.isTaskService = true
        service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        await service.choose(.normal)
        let path = "/tmp/orexin104-" + String(UUID().uuidString.prefix(8)) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = model()
        client.serviceSocket = path
        client.adoptServiceReply(service.taskControlReply())
        await client.choose(.desk)
        XCTAssertTrue(client.verifiedWork)
        await client.changeScreenSaverPrevention(false)
        XCTAssertFalse(client.sessions.choices.preventScreenSaver)
        XCTAssertFalse(service.sessions.choices.preventScreenSaver)
        // Another owner's awake requirement must remain effective.
        let other = try await service.registerWork(.init(title: "Independent awake task", screen: .awake))
        await client.refreshTaskService()
        await client.applyWorkScreenPolicy(now: Date())
        XCTAssertTrue(service.sessions.choices.preventScreenSaver)
        XCTAssertTrue(client.sessions.choices.preventScreenSaver)
        XCTAssertTrue(client.sessions.effectReport.screenSaver.contains("其他工作任务"))
        try await service.completeWork(other, exitCode: 0)
        await client.refreshTaskService()
        await client.applyWorkScreenPolicy(now: Date())
        XCTAssertFalse(service.sessions.choices.preventScreenSaver)
        await client.choose(.normal)
    }
    func testServiceEffectChangesImmediatelyRetainOtherOwnersInTheStatus() async throws {
        let service = model()
        service.isTaskService = true
        service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        await service.choose(.normal)
        let other = try await service.registerWork(.init(title: "Independent awake task", screen: .awake))
        let path = "/tmp/orexin104-" + String(UUID().uuidString.prefix(8)) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = model()
        client.serviceSocket = path
        client.adoptServiceReply(service.taskControlReply())
        await client.choose(.desk)
        await client.changeScreenSaverPrevention(false)
        XCTAssertTrue(client.workRequests.active.contains { $0.id == other.id })
        XCTAssertTrue(service.sessions.choices.preventScreenSaver)
        XCTAssertTrue(client.sessions.choices.preventScreenSaver)
        XCTAssertTrue(client.sessions.effectReport.screenSaver.contains("其他工作任务"))
        try await service.completeWork(other, exitCode: 0)
        await client.choose(.normal)
    }
    func testInheritedRuleClearsThePreviousRulesScreenOverride() async {
        let observations = Observations()
        let m = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "RuleSwitch." + UUID().uuidString)!,
                         triggerSource: observations, sessionEffects: Effects())
        m.workScreen.select(.systemIdle, for: .desk); m.triggers.enabled = true
        XCTAssertNil(m.triggers.save(.init(name: "A", enabled: true, conditions: [.init(kind: .acConnected)], preventScreenSaver: true)))
        XCTAssertNil(m.triggers.save(.init(name: "B", enabled: true, conditions: [.init(kind: .externalDisplay)])))
        await m.choose(.normal, automatic: true, startupRecovery: true)
        let now = Date()
        await m.tickFeatures(now: now, battery: nil)
        XCTAssertEqual(m.workScreen.behavior(for: .desk), .normalBrightness)
        observations.connected = false
        await m.tickFeatures(now: now.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(m.active, .desk)
        XCTAssertEqual(m.workScreen.behavior(for: .desk), .systemIdle)
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testIdleOwnerDoesNotBorrowAnotherOwnersDisplayRequirementForScreenSaver() async throws {
        let m = model()
        XCTAssertNil(m.preferences.object(forKey: "orexin.session.preventScreenSaver"))
        XCTAssertTrue(m.sessions.screenSaverChoice(keepingDisplayActive: true), "A missing preference should inherit the display choice")
        XCTAssertNil(m.preferences.object(forKey: "orexin.session.preventScreenSaver"), "Initialization should not create a saver preference")
        m.workScreen.select(.systemIdle, for: .desk)
        await m.choose(.desk)
        XCTAssertEqual(m.legacyWorkMode, .desk)
        XCTAssertTrue(m.sessions.screenSaverChoice(keepingDisplayActive: true), "This test requires an inherited screen saver choice")
        _ = try await m.registerWork(.init(title: "Awake without screen saver prevention", screen: .awake, preventScreenSaver: false))
        await m.applyWorkScreenPolicy(now: Date())
        XCTAssertEqual(m.sessions.screenPolicyPreventsSleep, true)
        XCTAssertEqual(m.workRequests.demand?.preventScreenSaver, false)
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testEnablingSaverPreventionDoesNotDependOnAnotherOwnersDisplayRequest() async throws {
        let m = model()
        m.workScreen.select(.systemIdle, for: .desk)
        await m.choose(.desk)
        let other = try await m.registerWork(.init(title: "Other awake task", screen: .awake, preventScreenSaver: false))
        await m.changeScreenSaverPrevention(true)
        XCTAssertEqual(m.workScreen.ownBehavior(for: .desk), .normalBrightness)
        XCTAssertEqual(m.workScreen.desktop, .systemIdle)
        try await m.completeWork(other, exitCode: 0)
        await m.applyWorkScreenPolicy(now: Date())
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        await m.choose(.normal)
    }
    func testScreenSwitchesChangeTheirOwnerWhenAnotherTaskUsesBackgroundMode() async throws {
        let m = model()
        await m.choose(.desk)
        let other = try await m.registerWork(.init(title: "Background idle task", mode: .background, screen: .idle))
        XCTAssertEqual(m.active, .background)
        XCTAssertEqual(m.legacyWorkMode, .desk)
        await m.changeDisplayPrevention(false)
        XCTAssertEqual(m.workScreen.ownBehavior(for: .desk), .systemIdle)
        XCTAssertFalse(m.sessions.choices.preventDisplaySleep)
        await m.changeScreenSaverPrevention(true)
        XCTAssertEqual(m.workScreen.ownBehavior(for: .desk), .normalBrightness)
        XCTAssertTrue(m.sessions.choices.preventScreenSaver)
        try await m.completeWork(other, exitCode: 0)
        await m.choose(.normal)
    }
    func testExplicitScreenPolicyTargetsItsOwnerWhenAnotherTaskUsesBackgroundMode() async throws {
        let m = model()
        m.workScreen.select(.systemIdle, for: .desk)
        await m.choose(.desk)
        let other = try await m.registerWork(.init(title: "Background idle task", mode: .background, screen: .idle))
        XCTAssertEqual(m.active, .background)
        await m.setWorkScreenBehavior(.normalBrightness)
        XCTAssertEqual(m.workScreen.desktop, .normalBrightness)
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        try await m.completeWork(other, exitCode: 0)
        await m.choose(.normal)
    }
    func testActiveScreenChangesDoNotOverwriteTheNextSessionDefaults() async {
        let m = model()
        await m.changeDisplayPrevention(true)
        await m.choose(.desk)
        await m.changeDisplayPrevention(false)
        XCTAssertEqual(m.workScreen.desktop, .normalBrightness)
        await m.choose(.normal)
        await m.choose(.desk)
        XCTAssertTrue(m.sessions.choices.preventDisplaySleep)
        await m.choose(.normal)
        await m.changeDisplayPrevention(false)
        await m.choose(.desk)
        await m.changeScreenSaverPrevention(true)
        XCTAssertEqual(m.workScreen.desktop, .systemIdle)
        await m.choose(.normal)
        await m.choose(.desk)
        XCTAssertFalse(m.sessions.choices.preventDisplaySleep)
        await m.choose(.normal)
    }
    func testEndingSessionClearsItsTemporaryScreenSettingsWhileAnotherTaskContinues() async throws {
        let m = model()
        await m.changeDisplayPrevention(false)
        await m.sessions.start()
        await m.changeDisplayPrevention(true)
        let other = try await m.registerWork(.init(title: "Independent idle task", screen: .idle))
        await m.sessions.end()
        XCTAssertNil(m.sessions.effectOverrides)
        XCTAssertNil(m.workScreen.runtimeBehavior)
        XCTAssertFalse(m.sessions.choices.preventDisplaySleep)
        try await m.completeWork(other, exitCode: 0)
        await m.choose(.normal)
    }
    func testScreenControlsExplainWhenOnlyAnIndependentTaskIsRunning() async throws {
        let m = model()
        let other = try await m.registerWork(.init(title: "Independent idle task", screen: .idle))
        XCTAssertNil(m.legacyWorkMode)
        XCTAssertTrue(m.screenEffectsControlledByOtherTasks)
        await m.changeDisplayPrevention(true)
        XCTAssertTrue(m.message.contains("其他任务"))
        XCTAssertFalse(m.sessions.choices.preventDisplaySleep)
        await m.changeScreenSaverPrevention(true)
        XCTAssertTrue(m.message.contains("其他任务"))
        XCTAssertFalse(m.sessions.choices.preventScreenSaver)
        try await m.completeWork(other, exitCode: 0)
    }
    func testServiceManualTransitionsClearTemporarySessionEffects() async throws {
        let service = model()
        service.isTaskService = true
        service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        await service.choose(.normal)
        let path = "/tmp/orexin104-" + String(UUID().uuidString.prefix(8)) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = model()
        client.serviceSocket = path
        client.adoptServiceReply(service.taskControlReply())
        await client.choose(.desk)
        await client.changeDisplayPrevention(false)
        XCTAssertFalse(service.sessions.choices.preventDisplaySleep)
        await client.choose(.normal)
        XCTAssertNil(client.workScreen.runtimeBehavior)
        await client.choose(.desk)
        XCTAssertTrue(service.sessions.choices.preventDisplaySleep)
        await client.changeScreenSaverPrevention(false)
        XCTAssertEqual(client.sessions.effectOverrides?.saver, false)
        await client.choose(.normal)
        XCTAssertNil(client.sessions.effectOverrides)
        await client.choose(.desk)
        XCTAssertTrue(service.sessions.choices.preventScreenSaver)
        client.sessions.setScreenSaverPrevention(false)
        await client.choose(.background)
        XCTAssertNil(client.sessions.effectOverrides)
        await client.choose(.normal)
    }
    func testNewServiceSessionDoesNotInheritPreviousManualScreenOverride() async throws {
        let service = model()
        service.isTaskService = true
        service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        await service.choose(.normal)
        let path = "/tmp/orexin104-" + String(UUID().uuidString.prefix(8)) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = model()
        client.serviceSocket = path
        client.adoptServiceReply(service.taskControlReply())
        await client.choose(.desk)
        await client.changeDisplayPrevention(false)
        XCTAssertFalse(service.sessions.choices.preventDisplaySleep)
        await client.sessions.start()
        XCTAssertNil(client.workScreen.runtimeBehavior)
        XCTAssertTrue(service.sessions.choices.preventDisplaySleep)
        await client.sessions.end()
    }
    func testOlderServiceExplainsWhyIndependentScreenSaverControlIsUnavailable() async {
        let m = model()
        m.serviceSocket = "/nonexistent"
        var reply = ControlReply()
        reply.service = TaskServiceInfo(stateDirectory: "/tmp"); reply.capabilities = ["notices-v1"]
        m.adoptServiceReply(reply)
        XCTAssertFalse(m.sessions.screenSaverControlAvailable)
        await m.changeScreenSaverPrevention(true)
        XCTAssertTrue(m.message.contains("重启后台服务"))
        XCTAssertFalse(m.sessions.preventScreenSaver)
    }
    func testOldRequestPayloadRemainsCompatibleWithTheNewOptionalChoice() throws {
        let data = Data(#"{"title":"Legacy","source":"interface","mode":"desk","screen":"awake","teardown":"restore"}"#.utf8)
        var spec = try ControlCoding.decode(WorkRequestSpec.self, from: data)
        XCTAssertNil(spec.preventScreenSaver)
        spec.preventScreenSaver = false
        let restored = try ControlCoding.decode(WorkRequestSpec.self, from: ControlCoding.encode(spec))
        XCTAssertEqual(restored.preventScreenSaver, false)
    }
    func testPreconfiguredDisplayChoiceAppliesWhenStartingBackgroundSession() async {
        let m = model()
        m.sessions.defaultMode = .background
        for enabled in [false, true] {
            await m.choose(.normal)
            await m.changeDisplayPrevention(enabled)
            await m.sessions.start()
            XCTAssertEqual(m.active, .background)
            XCTAssertEqual(m.sessions.choices.preventDisplaySleep, enabled)
            await m.sessions.end()
        }
    }
    func testOptionalNativeEditorReview() async throws {
        guard ProcessInfo.processInfo.environment["OREXIN_EFFECT_UI"] == "1" else { throw XCTSkip("Opt-in isolated native UI review") }
        let m = model()
        m.sessions.cursorAccessCheck = { false }
        m.sessions.cursorAccessRequest = { false }
        m.sessions.cursorAccessSettings = { true }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OREXIN_UI_OUTPUT"] ?? "/tmp/orexin-104-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 650, height: 740),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Orexin · 1.0.4 isolated UI review"; window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.close() }
        let ac = TriggerCondition(kind: .acConnected)
        let application = TriggerCondition(kind: .appRunning, value: "com.apple.finder")
        let cpu = TriggerCondition(kind: .cpuAbove, value: "75")
        let rules = [
            ("power", TriggerRule(name: "外接电源连接", enabled: false, conditions: [ac])),
            ("application", TriggerRule(name: "应用 / 进程守护", enabled: false, conditions: [.init(kind: .appRunning)])),
            ("nested", TriggerRule(name: "工作应用与电源条件", enabled: true, conditions: [application],
                                   expression: .all([.condition(application), .any([.condition(ac), .not(.condition(cpu))])])))
        ]
        for (name, rule) in rules {
            let host = NSHostingView(rootView: TriggerRuleEditor(rule: rule, controller: m.triggers, finish: {}).preferredColorScheme(.dark))
            window.contentView = host; window.setContentSize(host.fittingSize)
            window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(350)); host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.bounds.width, 650, accuracy: 1)
            XCTAssertLessThanOrEqual(host.bounds.height, NSScreen.main?.visibleFrame.height ?? 836)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("rule-" + name + ".png"))
        }
        // A separate mocked work session allows interactive review without touching live power.
        await m.choose(.desk)
        let host = NSHostingView(rootView: ScrollView { SessionsView(model: m, controller: m.sessions).padding(20) }.preferredColorScheme(.dark))
        window.setContentSize(.init(width: 1000, height: 800)); window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(350)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("session-controls.png"))
        if ProcessInfo.processInfo.environment["OREXIN_UI_HOLD"] == "1" {
            try await Task.sleep(for: .seconds(60))
        }
        await m.choose(.normal)
    }
}
