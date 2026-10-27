// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
import AppKit
@testable import WakeMac
import WakeMacCore

@MainActor final class DisplayWakeRecoveryTests: XCTestCase {
    private let awake = DisplayState(lidClosed: false, builtInAsleep: false, sessionLocked: false)
    private let closed = DisplayState(lidClosed: true, builtInAsleep: true, sessionLocked: true)

    private func policy() -> WorkScreenPolicy {
        WorkScreenPolicy(preferences: UserDefaults(suiteName: "WakeRecovery." + UUID().uuidString)!)
    }

    func testLidOpeningRestoresBrightnessUntilNextCloseWithoutChangingSavedPolicy() async {
        let screen = policy(), now = Date()
        var brightness: Float = 0.72
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestSleep = { XCTFail("Returning to the screen must not request display sleep") }
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        XCTAssertEqual(brightness, 0)
        await screen.tick(mode: .background, working: true, state: closed, onBattery: false, now: now.addingTimeInterval(60))
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(61))
        XCTAssertEqual(brightness, 0.72, accuracy: 0.001)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(600))
        XCTAssertEqual(brightness, 0.72, accuracy: 0.001)
        XCTAssertEqual(screen.background, .dim)
        await screen.tick(mode: .background, working: true, state: closed, onBattery: false, now: now.addingTimeInterval(601))
        XCTAssertEqual(brightness, 0)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(602))
        XCTAssertEqual(brightness, 0.72, accuracy: 0.001)
    }

    func testUnlockAndDisplayWakeRecoverEvenWhenLidDoesNotChange() async {
        for returnedFrom in [DisplayState(lidClosed: false, builtInAsleep: false, sessionLocked: true),
                             DisplayState(lidClosed: false, builtInAsleep: true, sessionLocked: false)] {
            let screen = policy(), now = Date()
            var brightness: Float = 0.64
            screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
            screen.requestSleep = { XCTFail("Unexpected display sleep") }
            await screen.tick(mode: .background, working: true, state: returnedFrom, onBattery: false, now: now)
            await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(6))
            XCTAssertEqual(brightness, 0.64, accuracy: 0.001)
        }
    }

    func testWakeRecoverySurvivesRenewedDimRequestsAndExplicitSelectionCanReapplyDim() async {
        let screen = policy(), now = Date()
        var brightness: Float = 0.8
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestBehavior = .dim
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        screen.resumeAfterDisplayWake()
        screen.requestBehavior = .systemIdle
        screen.requestBehavior = .dim
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(6))
        XCTAssertEqual(brightness, 0.8, accuracy: 0.001)
        XCTAssertEqual(screen.behavior(for: .background), .normalBrightness)
        screen.select(.dim, for: .background)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(7))
        XCTAssertEqual(brightness, 0)
    }

    func testImmediateSleepWakeRestoresVisibleBrightnessOverDimPreset() async {
        let screen = policy(), now = Date()
        var brightness: Float = 0.6, sleeps = 0
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestSleep = { sleeps += 1 }
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        screen.runtimeBehavior = .immediateSleep
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(1))
        screen.resumeAfterDisplayWake()
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(7))
        XCTAssertEqual(sleeps, 1)
        XCTAssertEqual(brightness, 0.6, accuracy: 0.001)
        XCTAssertEqual(screen.background, .dim)
    }

    func testExplicitDimSelectionReachesBackgroundServiceWithoutStoppingTasks() async throws {
        let serverModel = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "WakeService." + UUID().uuidString)!)
        serverModel.isTaskService = true
        serverModel.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        serverModel.thermalStateProvider = { .nominal }
        _ = try await serverModel.registerWork(.init(title: "ongoing", mode: .background, screen: .dim))
        let screen = policy(), now = Date()
        var brightness: Float = 0.7
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestSleep = { XCTFail("No display sleep expected") }
        serverModel.workScreen = screen
        screen.requestBehavior = .dim
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        screen.resumeAfterDisplayWake()
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(6))
        XCTAssertEqual(brightness, 0.7, accuracy: 0.001)

        let path = "/tmp/orx-wake-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await serverModel.handleTaskControl($0) }
        defer { server.stop() }
        let client = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "WakeClient." + UUID().uuidString)!)
        client.serviceSocket = path
        client.adoptServiceReply(serverModel.taskControlReply())
        let ids = serverModel.workRequests.active.map(\.id)
        await client.setWorkScreenBehavior(.dim)
        XCTAssertEqual(brightness, 0)
        XCTAssertEqual(serverModel.workRequests.active.map(\.id), ids)
        XCTAssertEqual(serverModel.active, .background)
    }

    func testServiceWakeAndUnlockNotificationsRecoverWithoutAnObservedSleepTick() async {
        let screen = policy(), now = Date()
        let workspace = NotificationCenter(), session = NotificationCenter()
        var brightness: Float = 0.68
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.startObservingUserReturn(workspaceCenter: workspace, sessionCenter: session)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        XCTAssertEqual(brightness, 0, "An event before work starts must not override the new preset")
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(1))
        XCTAssertEqual(brightness, 0.68, accuracy: 0.001)
        screen.select(.dim, for: .background)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(2))
        XCTAssertEqual(brightness, 0)
        session.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(3))
        XCTAssertEqual(brightness, 0.68, accuracy: 0.001)
    }

    func testDeskDisplaySwitchDoesNotResumeAnIndependentBackgroundTasksDimming() async throws {
        let service = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "WakeDeskService." + UUID().uuidString)!)
        service.isTaskService = true; service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        service.thermalStateProvider = { .nominal }
        let background = try await service.registerWork(.init(title: "background", mode: .background, screen: .dim))
        let screen = policy(), now = Date()
        var brightness: Float = 0.7
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestSleep = { XCTFail("No display sleep expected") }
        service.workScreen = screen; screen.requestBehavior = .dim
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        screen.resumeAfterDisplayWake()
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(6))

        let path = "/tmp/orx-wake-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "WakeDeskClient." + UUID().uuidString)!)
        client.serviceSocket = path; client.adoptServiceReply(service.taskControlReply())
        await client.choose(.desk)
        await client.changeDisplayPrevention(false)
        await client.changeDisplayPrevention(true)
        await client.disconnectInterface()
        await service.applyWorkScreenPolicy(now: now.addingTimeInterval(10))
        XCTAssertEqual(service.workRequests.active.map(\.id), [background.id])
        XCTAssertEqual(brightness, 0.7, accuracy: 0.001)
    }

    func testEndingWorkClearsWakeRecoveryBeforeTheNextSession() async throws {
        let screen = policy(), now = Date()
        var brightness: Float = 0.55
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        screen.resumeAfterDisplayWake()
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(1))
        try screen.restore()
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(2))
        XCTAssertEqual(brightness, 0)
        try screen.restore()
        XCTAssertEqual(brightness, 0.55, accuracy: 0.001)
    }

    func testFailedSleepRequestDoesNotPretendTheUserReturned() async {
        let screen = policy(), now = Date()
        var brightness: Float = 0.65
        screen.readBrightness = { brightness }; screen.writeBrightness = { brightness = $0 }
        screen.requestSleep = { throw ModeError("Expected test failure") }
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now)
        screen.runtimeBehavior = .immediateSleep
        await screen.tick(mode: .background, working: true, state: awake, onBattery: false, now: now.addingTimeInterval(1))
        XCTAssertEqual(screen.behavior(for: .background), .dim)
        XCTAssertEqual(brightness, 0)
    }
}
