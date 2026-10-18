import XCTest
import Combine
@testable import WakeMac
import WakeMacCore

@MainActor final class TaskServiceTests: XCTestCase {
    private final class Effects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport { .init(displayAssertionActive: working && choices.preventDisplaySleep) }
        func release() {}
    }
    private func model() async -> AppModel {
        let value = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "ServiceTests." + UUID().uuidString)!, sessionEffects: Effects())
        value.thermalStateProvider = { .nominal }
        value.isTaskService = true
        value.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        await value.choose(.normal)
        return value
    }
    func testPackagedCLIResolvesServiceInMacOSDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = root.appendingPathComponent("Orexin.app/Contents/Helpers/orexin")
        let service = root.appendingPathComponent("Orexin.app/Contents/MacOS/Orexin")
        for file in [cli, service] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        XCTAssertEqual(try TaskServiceLauncher.executable(near: cli).standardizedFileURL, service.standardizedFileURL)
    }

    func testServiceRefusesShutdownWithActiveWork() async throws {
        let value = await model()
        let handle = WorkRequestHandle()
        let registered = await value.handleTaskControl(.init("register", handle: handle, spec: .init(title: "task")))
        XCTAssertTrue(registered.ok)
        let stopped = await value.handleTaskControl(.init("service-stop"))
        XCTAssertFalse(stopped.ok)
        XCTAssertEqual(value.workRequests.active.count, 1)
    }
    func testGroupKeepsOneRequestAcrossCommandsAndIndependentRequestSurvives() async throws {
        let value = await model()
        let external = try await value.registerWork(.init(title: "external"))
        let plan = ExecutionPlan(title: "group", tasks: [.init(id: "a", command: "true", directory: "/tmp"), .init(id: "b", command: "true", directory: "/tmp", dependencies: ["a"])])
        value.planCommandRunner = { _, _, log in .init(exitCode: 0, logURL: log, truncated: false) }
        let run = try await value.startPlan(plan)
        for _ in 0..<100 where value.planRuns.first(where: { $0.id == run.id })?.state == .running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(value.planRuns.first?.state, .succeeded)
        XCTAssertEqual(value.workRequests.active.map(\.id), [external.id])
        XCTAssertEqual(value.workRequests.records.filter { $0.spec.source == "plan" }.count, 1)
    }
    func testInvalidPlanDoesNotRegisterOrRunAnything() async throws {
        let value = await model()
        do { _ = try await value.startPlan(.init(title: "bad", tasks: [])); XCTFail("accepted invalid plan") } catch {}
        XCTAssertTrue(value.workRequests.records.isEmpty)
        XCTAssertTrue(value.planRuns.isEmpty)
    }
    func testTransientPowerVerificationPausesRatherThanCancelsPlan() async throws {
        let value = await model()
        let plan = ExecutionPlan(title: "transition", tasks: [.init(id: "a", command: "true", directory: "/tmp"), .init(id: "b", command: "true", directory: "/tmp", dependencies: ["a"])])
        var run = try PlanRun(plan: plan)
        let handle = try await value.registerWork(.init(title: "transition", source: "plan"), handle: .init(id: run.id))
        _ = run.schedule(now: Date())
        value.planRuns = [run]; value.planHandles[run.id] = handle
        let snapshot = value.snapshot
        value.busy = true; value.active = nil; value.snapshot = nil
        await value.advancePlans()
        XCTAssertEqual(value.planRuns[0].state, .running)
        XCTAssertEqual(value.planRuns[0].tasks[1].state, .pending)
        value.busy = false; value.active = .desk; value.snapshot = snapshot
        await value.advancePlans()
        XCTAssertEqual(value.planRuns[0].state, .running)
    }
    func testVisibleBatteryCountdownCancellationReachesService() async throws {
        let value = await model()
        _ = try await value.registerWork(.init(title: "protected"))
        let now = Date()
        _ = value.automation.evaluate(now: now, mode: .desk, battery: .init(percent: 5, onBattery: true))
        XCTAssertNotNil(value.automation.batterySleepAt)
        let directory = URL(fileURLWithPath: "/tmp/orxb-" + UUID().uuidString.prefix(8))
        let path = directory.appendingPathComponent("control.sock").path
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.adoptServiceReply(value.taskControlReply())
        client.cancelVisibleCountdown()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(value.automation.batterySleepAt)
        let actions = value.automation.evaluate(now: now.addingTimeInterval(61), mode: .desk, battery: .init(percent: 5, onBattery: true))
        XCTAssertFalse(actions.contains(.sleepForBattery))
        XCTAssertEqual(value.workRequests.active.count, 1)
    }
    func testShutdownAcknowledgementFencesNewWork() async throws {
        let value = await model()
        let stopped = await value.handleTaskControl(.init("service-stop"))
        XCTAssertTrue(stopped.ok)
        let registered = await value.handleTaskControl(.init("register", handle: .init(), spec: .init(title: "too late")))
        XCTAssertFalse(registered.ok)
        XCTAssertTrue(value.workRequests.active.isEmpty)
    }
    func testLauncherWaitsForExistingServiceReadiness() async throws {
        actor Readiness {
            var count = 0
            func reply() -> ControlReply {
                count += 1
                var reply = ControlReply(ok: count > 1, error: count > 1 ? nil : "Task service is starting")
                reply.service = TaskServiceInfo(stateDirectory: "/tmp")
                return reply
            }
        }
        let readiness = Readiness()
        let path = "/tmp/orxs-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { _ in await readiness.reply() }
        defer { server.stop() }
        let reply = try await Task.detached {
            try TaskServiceLauncher.start(executable: URL(fileURLWithPath: "/nonexistent"), socket: path)
        }.value
        XCTAssertTrue(reply.ok)
    }

    func testClientExitAndReconnectionPreserveIndependentRequests() async throws {
        let value = await model()
        let external = try await value.registerWork(.init(title: "independent", source: "external"))
        let path = "/tmp/orxu-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh()
        XCTAssertEqual(value.workRequests.active.map(\.id), [external.id])
        await client.choose(.desk)
        XCTAssertEqual(value.workRequests.active.count, 2)
        var quit = false; client.quitApplication = { quit = true }
        await client.requestQuit()
        XCTAssertTrue(quit)
        XCTAssertEqual(value.workRequests.active.map(\.id), [external.id])
        let reopened = await model(); reopened.isTaskService = false; reopened.serviceSocket = path
        await reopened.refresh()
        XCTAssertEqual(reopened.workRequests.active.map(\.id), [external.id])
        XCTAssertTrue(reopened.requestSatisfied(value.workRequests.active[0].spec))
    }

    func testClientRecoversAfterServiceConnectionReturns() async throws {
        let value = await model()
        let path = "/tmp/orxr-" + UUID().uuidString.prefix(8) + "/control.sock"
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        await client.refresh()
        XCTAssertTrue(client.error)
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        await client.refresh()
        XCTAssertFalse(client.error)
        XCTAssertEqual(client.active, .normal)
    }

    func testRepeatedInterfaceTicksKeepVerifiedWorkWithoutModeTransitions() async throws {
        let value = await model()
        let path = "/tmp/orxt-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh()
        await client.choose(.desk)
        XCTAssertTrue(client.verifiedWork)
        let handle = try XCTUnwrap(client.interfaceHandle)
        let lease = try XCTUnwrap(value.workRequests.active.first?.leaseExpiresAt)
        var transitions: [Bool] = []
        let observation = client.$busy.dropFirst().sink { transitions.append($0) }
        defer { observation.cancel() }

        for _ in 0..<8 {
            await client.tick(battery: nil)
            XCTAssertTrue(client.verifiedWork)
            XCTAssertEqual(client.interfaceHandle, handle)
        }

        XCTAssertFalse(transitions.contains(true), "Heartbeat reconciliation must not show the mode-switching UI")
        XCTAssertEqual(value.workRequests.active.map(\.id), [handle.id])
        XCTAssertGreaterThan(try XCTUnwrap(value.workRequests.active.first?.leaseExpiresAt), lease)
    }

    func testInterfaceScreenChangeAndErrorRecoveryStillReconcile() async throws {
        let value = await model()
        let path = "/tmp/orxc-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh()
        await client.choose(.desk)
        let original = try XCTUnwrap(client.interfaceHandle)
        var transitions: [Bool] = []
        let observation = client.$busy.dropFirst().sink { transitions.append($0) }
        defer { observation.cancel() }

        await client.setWorkScreenBehavior(.normalBrightness)
        XCTAssertNotEqual(client.interfaceHandle, original)
        XCTAssertEqual(value.workRequests.active.count, 1)
        XCTAssertEqual(value.workRequests.active.first?.spec.screen, .awake)
        XCTAssertTrue(transitions.contains(true))
        XCTAssertTrue(client.verifiedWork)

        transitions.removeAll()
        client.error = true
        await client.reconcileWorkRequests()
        XCTAssertTrue(transitions.contains(true), "An existing error must still be rechecked")
        XCTAssertTrue(client.verifiedWork)
    }

}
