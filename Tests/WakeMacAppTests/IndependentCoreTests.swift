import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor final class IndependentCoreTests: XCTestCase {
    final class Effects: SessionEffectManaging {
        var updates = 0
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
            updates += 1
            return .init(displayAssertionActive: working && choices.preventDisplaySleep,
                         screenSaverAssertionActive: working && choices.preventScreenSaver)
        }
        func release() {}
    }
    func model(_ effects: Effects? = nil) async -> AppModel {
        let value = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "IndependentCore." + UUID().uuidString)!, sessionEffects: effects ?? Effects())
        value.thermalStateProvider = { .nominal }; value.isTaskService = true
        value.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        await value.choose(.normal)
        return value
    }
    final class Observations: TriggerObservationSource {
        var connected = true
        func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
            var value = TriggerSnapshot(); value.externalDisplay = connected; return value
        }
    }
    func testServiceTickOwnsTriggerEvaluationWithoutInterface() async {
        let source = Observations()
        let core = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: UUID().uuidString)!,
                            triggerSource: source, sessionEffects: Effects())
        core.isTaskService = true; core.thermalStateProvider = { .nominal }
        core.triggers.save(TriggerRule(name: "Display", enabled: true, conditions: [TriggerCondition(kind: .externalDisplay)]))
        await core.choose(.normal, automatic: true, startupRecovery: true)
        let now = Date()
        await core.tick(now: now, battery: nil)
        XCTAssertEqual(core.active, .desk)
        source.connected = false
        await core.tick(now: now.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(core.active, .normal)
    }
    func testIntentionalCoreStopPausesPollingAndRecovery() async throws {
        let core = await model()
        let socket = "/tmp/orx-core-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in await core.handleTaskControl(request) }
        defer { server.stop() }
        let gui = AppModel(backend: ServiceModeBackend(path: socket), preferences: UserDefaults(suiteName: UUID().uuidString)!, sessionEffects: Effects())
        gui.serviceSocket = socket; gui.serviceRecoveryEnabled = true
        await gui.refreshTaskService()
        await gui.stopCoreService()
        XCTAssertTrue(gui.corePaused)
        XCTAssertFalse(gui.serviceRecoveryEnabled)
        XCTAssertNil(gui.serviceInfo)
        await gui.refreshTaskService()
        XCTAssertFalse(gui.error)
    }
    actor SuspendedCredentialStore: UnlockedWorkCredentialStore {
        var continuation: CheckedContinuation<Void, Never>?
        var saving = false
        func load() async throws -> Data? { nil }
        func save(_ password: Data) async throws {
            saving = true
            await withCheckedContinuation { continuation = $0 }
        }
        func delete() async throws {}
        func resume() { continuation?.resume(); continuation = nil }
    }
    private func cancelDuringCredentialSave(startSession: Bool, newerWork: Bool) async throws {
        let core = await model(), store = SuspendedCredentialStore()
        let socket = "/tmp/orx-auth-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in
            if request.operation == "unlocked-prepare" {
                return await MainActor.run {
                    core.pendingUnlockedGrantID = request.id
                    var reply = core.taskControlReply(); reply.unlockedWorkAuthorized = false; return reply
                }
            }
            if ["unlocked-ready", "unlocked-finish"].contains(request.operation) { return await core.taskControlReply() }
            return await core.handleTaskControl(request)
        }
        defer { server.stop() }
        let preferences = UserDefaults(suiteName: UUID().uuidString)!
        preferences.set(true, forKey: "orexin.work.keepUnlocked")
        preferences.set(true, forKey: UnlockedWorkCredentials.preferenceKey)
        let gui = AppModel(backend: ServiceModeBackend(path: socket), preferences: preferences, sessionEffects: Effects())
        gui.serviceSocket = socket
        gui.unlockedCredentials = UnlockedWorkCredentials(preferences: preferences, store: store)
        gui.requestUnlockedWorkPassword = { Data("test-only".utf8) }
        gui.disableUnlockedWorkScreenLock = { _ in }
        let starting = Task {
            if startSession { await gui.sessions.start() }
            else { await gui.choose(.desk) }
        }
        while await !store.saving { await Task.yield() }
        await gui.choose(.normal)
        if newerWork { await core.choose(.desk) }
        await store.resume(); await starting.value
        XCTAssertFalse(core.sessions.isActive)
        XCTAssertEqual(core.active, newerWork ? .desk : .normal)
        XCTAssertEqual(core.manualWorkMode, newerWork ? .desk : nil)
        await core.choose(.normal)
    }
    func testStopDuringModeCredentialSaveCannotRestartWork() async throws {
        try await cancelDuringCredentialSave(startSession: false, newerWork: false)
    }
    func testStopDuringSessionCredentialSavePreservesNewerCoreWork() async throws {
        try await cancelDuringCredentialSave(startSession: true, newerWork: true)
    }
    func testAuthorizationCancelOnlyRestoresMatchingIdleGrant() async throws {
        let core = await model(), first = UUID(), newer = UUID()
        core.pendingUnlockedGrantID = newer
        _ = await core.handleTaskControl(.init("unlocked-cancel", id: first))
        XCTAssertEqual(core.pendingUnlockedGrantID, newer)
        _ = await core.handleTaskControl(.init("unlocked-cancel", id: newer))
        XCTAssertNil(core.pendingUnlockedGrantID)
        await core.choose(.desk)
        core.pendingUnlockedGrantID = newer
        _ = await core.handleTaskControl(.init("unlocked-cancel", id: newer))
        XCTAssertEqual(core.active, .desk)
        await core.choose(.normal)
    }
    func testStatisticsSnapshotAndRemoteResetRemainAuthoritative() async throws {
        let core = await model()
        core.behavior.statisticsEnabled = true
        let epoch = Date()
        _ = core.behavior.sample(working: true, closed: true, docked: false, now: epoch)
        _ = core.behavior.sample(working: true, closed: true, docked: false, now: epoch.addingTimeInterval(10))
        let gui = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: UUID().uuidString)!, sessionEffects: Effects())
        gui.adoptServiceReply(core.taskControlReply())
        XCTAssertEqual(gui.behavior.awakeSeconds, 10)
        XCTAssertEqual(gui.behavior.lidSeconds, 10)
        XCTAssertEqual(gui.behavior.activations, 1)
        XCTAssertEqual(gui.preferences.double(forKey: "orexin.statistics.awakeSeconds"), 0)
        let socket = "/tmp/orx-stat-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in await core.handleTaskControl(request) }
        defer { server.stop() }
        gui.serviceSocket = socket
        await gui.resetCoreStatistics()
        XCTAssertEqual(core.behavior.awakeSeconds, 0)
        XCTAssertEqual(gui.behavior.awakeSeconds, 0)
        _ = core.behavior.sample(working: true, closed: true, docked: false, now: epoch.addingTimeInterval(12))
        core.behavior.saveStatistics()
        gui.adoptServiceReply(core.taskControlReply())
        XCTAssertEqual(core.behavior.awakeSeconds, 0)
        XCTAssertEqual(gui.behavior.activations, 0)
    }
    func testOlderServiceRequiresUpgradeAndActiveWorkBlocksRestart() async throws {
        let core = await model()
        let handle = try await core.registerWork(.init(title: "active job"))
        let socket = "/tmp/orx-old-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in
            var reply = await core.handleTaskControl(request)
            reply.capabilities = ["notices-v1", "session-effects-v1"]; reply.coreRuntime = nil
            return reply
        }
        defer { server.stop() }
        let gui = AppModel(backend: ServiceModeBackend(path: socket), preferences: UserDefaults(suiteName: UUID().uuidString)!, sessionEffects: Effects())
        gui.serviceSocket = socket
        gui.launchTaskService = { _, _ in
            var reply = core.taskControlReply(); reply.capabilities = ["notices-v1", "session-effects-v1"]; reply.coreRuntime = nil; return reply
        }
        await gui.connectTaskService()
        XCTAssertTrue(gui.coreUpgradeRequired)
        XCTAssertTrue(gui.error)
        await gui.restartCoreService()
        XCTAssertFalse(gui.corePaused)
        XCTAssertTrue(gui.coreUpgradeRequired)
        XCTAssertEqual(core.workRequests.active.map(\.id), [handle.id])
        await gui.choose(.normal)
        XCTAssertFalse(gui.error, gui.message)
        XCTAssertTrue(core.workRequests.active.isEmpty)
        XCTAssertEqual(core.active, .normal)
    }
    func testIdleOldServiceCanRestartIntoCurrentCore() async throws {
        let old = await model(), replacement = await model()
        let socket = "/tmp/orx-upg-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in
            var reply = await old.handleTaskControl(request)
            reply.capabilities = ["notices-v1", "session-effects-v1"]; reply.coreRuntime = nil
            return reply
        }
        old.stopTaskService = { server.stop() }
        defer { server.stop() }
        let gui = AppModel(backend: ServiceModeBackend(path: socket), preferences: UserDefaults(suiteName: UUID().uuidString)!, sessionEffects: Effects())
        gui.serviceSocket = socket
        var launches = 0
        gui.launchTaskService = { _, _ in
            launches += 1
            if launches == 1 {
                var reply = old.taskControlReply(); reply.capabilities = ["notices-v1", "session-effects-v1"]; reply.coreRuntime = nil; return reply
            }
            return replacement.taskControlReply()
        }
        await gui.connectTaskService()
        XCTAssertTrue(gui.coreUpgradeRequired)
        await gui.restartCoreService()
        XCTAssertEqual(launches, 2)
        XCTAssertFalse(gui.coreUpgradeRequired)
        XCTAssertFalse(gui.corePaused)
        XCTAssertFalse(gui.error)
        XCTAssertEqual(gui.serviceInfo?.instanceID, replacement.serviceInfo?.instanceID)
    }
    func testManualWorkBelongsToCoreAndBlocksIdleStop() async throws {
        let core = await model()
        var request = ControlMessage("core-mode"); request.mode = .desk
        let reply = await core.handleTaskControl(request)
        XCTAssertTrue(reply.ok, reply.error ?? "")
        XCTAssertEqual(core.manualWorkMode, .desk)
        XCTAssertTrue(core.workRequests.active.isEmpty)
        let stopped = await core.handleTaskControl(.init("service-stop"))
        XCTAssertFalse(stopped.ok)
        XCTAssertEqual(core.active, .desk)
        await core.choose(.normal)
    }
    func testSessionAndEffectsContinueAfterInterfaceDisconnect() async throws {
        let effects = Effects(), core = await model(effects)
        let socket = "/tmp/orx-core-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in await core.handleTaskControl(request) }
        defer { server.stop() }
        let gui = AppModel(backend: ServiceModeBackend(path: socket), preferences: UserDefaults(suiteName: "CoreGUI." + UUID().uuidString)!, sessionEffects: Effects())
        gui.serviceSocket = socket
        gui.sessions.endCondition = .duration; gui.sessions.durationMinutes = 2
        await gui.sessions.start()
        XCTAssertTrue(core.sessions.isActive)
        XCTAssertTrue(gui.sessions.isActive)
        let deadline = try XCTUnwrap(core.sessions.deadline)
        await gui.disconnectInterface()
        XCTAssertTrue(core.sessions.isActive)
        let previous = effects.updates
        await core.applyWorkScreenPolicy(now: deadline.addingTimeInterval(-30))
        XCTAssertGreaterThan(effects.updates, previous)
        let extended = await gui.sessions.extendRemotely(minutes: 1)
        XCTAssertTrue(extended)
        XCTAssertEqual(core.sessions.deadline, deadline.addingTimeInterval(60))
        await core.sessions.end()
    }
    func testTimedSessionEndsWithoutInterface() async throws {
        let core = await model()
        core.sessions.endCondition = .duration; core.sessions.durationMinutes = 1
        await core.sessions.start()
        let deadline = try XCTUnwrap(core.sessions.deadline)
        await core.sessions.tick(now: deadline)
        XCTAssertFalse(core.sessions.isActive)
        XCTAssertEqual(core.active, .normal)
    }
    func testReconnectAdoptsCoreAndDoesNotReplayManualIntent() async throws {
        let core = await model()
        let socket = "/tmp/orx-core-\(UUID().uuidString.prefix(8))/control.sock"
        let server = try LocalControlServer(path: socket) { request in await core.handleTaskControl(request) }
        defer { server.stop() }
        let gui = AppModel(backend: ServiceModeBackend(path: socket), preferences: UserDefaults(suiteName: UUID().uuidString)!, sessionEffects: Effects())
        gui.serviceSocket = socket; gui.manualWorkMode = .background
        gui.connectedServiceInstanceID = UUID()
        await gui.refreshTaskService()
        XCTAssertNil(gui.manualWorkMode)
        XCTAssertNil(core.manualWorkMode)
        XCTAssertEqual(core.active, .normal)
        XCTAssertEqual(gui.serviceInfo?.instanceID, core.serviceInfo?.instanceID)
    }
    func testSnapshotRoundTripPreservesRuntimeDeadline() async throws {
        let core = await model()
        core.sessions.endCondition = .duration; core.sessions.durationMinutes = 1
        await core.sessions.start()
        let reply = core.taskControlReply()
        let snapshot = try ControlCoding.decode(CoreRuntimeSnapshot.self, from: XCTUnwrap(reply.coreRuntime))
        XCTAssertTrue(snapshot.session.active)
        XCTAssertNotNil(snapshot.session.deadline)
        XCTAssertTrue(reply.capabilities?.contains("independent-core-v1") == true)
        await core.sessions.end()
    }
}
