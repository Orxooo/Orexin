import XCTest
import Combine
@testable import WakeMac
import WakeMacCore

private actor ReplacingTaskService {
    let first: AppModel, second: AppModel
    var replaced = false
    init(first: AppModel, second: AppModel) { self.first = first; self.second = second }
    func reply(_ request: ControlMessage) async -> ControlReply {
        if request.operation == "core-mode" { replaced = true }
        return await (replaced ? second : first).handleTaskControl(request)
    }
}

private actor InterceptServiceReply {
    var operation: String?
    func arm(_ operation: String) { self.operation = operation }
    func take(_ operation: String) -> Bool {
        guard self.operation == operation else { return false }
        self.operation = nil; return true
    }
}

@MainActor final class TaskServiceTests: XCTestCase {
    private final class Effects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport { .init(displayAssertionActive: working && choices.preventDisplaySleep, screenSaverAssertionActive: working && choices.preventScreenSaver) }
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

    func testPackagedCLIAndInterfacePreferDedicatedCore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = root.appendingPathComponent("Orexin.app/Contents/Helpers/orexin")
        let interface = root.appendingPathComponent("Orexin.app/Contents/MacOS/Orexin")
        let core = root.appendingPathComponent("Orexin.app/Contents/Helpers/OrexinCore")
        for file in [cli, interface, core] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        XCTAssertEqual(try TaskServiceLauncher.executable(near: cli).standardizedFileURL, core.standardizedFileURL)
        XCTAssertEqual(try TaskServiceLauncher.executable(near: interface).standardizedFileURL, core.standardizedFileURL)
        XCTAssertEqual(try TaskServiceLauncher.executable(near: core).standardizedFileURL, interface.standardizedFileURL)
    }


    func testSleepRequestReportsThatSleepWasRequested() async throws {
        let service = await model()
        let path = "/tmp/orx-sleep-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model()
        client.isTaskService = false; client.serviceSocket = path
        await client.choose(.normal, sleep: true)
        XCTAssertFalse(client.error, client.message)
        XCTAssertEqual(client.message, "已向系统发送休眠请求。")
    }


    func testBusyCoreRejectsSleepWithoutQueuingAStop() async throws {
        let service = await model()
        let handle = try await service.registerWork(.init(title: "existing work"))
        service.busy = true
        let reply = await service.handleTaskControl(.init("sleep-now"))
        XCTAssertFalse(reply.ok)
        XCTAssertFalse(service.queuedUserStop)
        XCTAssertEqual(service.workRequests.active.map(\.id), [handle.id])
        service.busy = false
        try await service.completeWork(handle, exitCode: 0)
    }

    func testServiceStopsAfterGraphicalSessionEnds() async throws {
        let value = await model(), runtime = TaskServiceRuntime()
        runtime.model = value
        let stopped = expectation(description: "Old graphical session service exits")
        value.stopTaskService = { stopped.fulfill() }
        let connected = await runtime.stopAfterSessionEnds(sessionAvailable: true)
        XCTAssertFalse(connected)
        let ended = await runtime.stopAfterSessionEnds(sessionAvailable: false)
        XCTAssertTrue(ended)
        XCTAssertTrue(value.serviceStopping)
        XCTAssertEqual(value.active, .normal)
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testServiceWaitsForIndependentWorkBeforeEndingLostSession() async throws {
        let value = await model(), runtime = TaskServiceRuntime()
        runtime.model = value
        let handle = try await value.registerWork(.init(title: "independent"))
        _ = await runtime.stopAfterSessionEnds(sessionAvailable: true)
        let busy = await runtime.stopAfterSessionEnds(sessionAvailable: false)
        XCTAssertFalse(busy)
        XCTAssertFalse(value.serviceStopping)
        XCTAssertEqual(value.workRequests.active.map(\.id), [handle.id])
        try await value.completeWork(handle, exitCode: 0)
        let ended = await runtime.stopAfterSessionEnds(sessionAvailable: false)
        XCTAssertTrue(ended)
        XCTAssertTrue(value.serviceStopping)
    }

    func testServiceWithoutAnObservedGraphicalSessionKeepsRunning() async {
        let value = await model(), runtime = TaskServiceRuntime()
        runtime.model = value
        let ended = await runtime.stopAfterSessionEnds(sessionAvailable: false)
        XCTAssertFalse(ended)
        XCTAssertFalse(value.serviceStopping)
    }

    func testServiceKeepsRunningWhileGraphicalSessionExists() async {
        let value = await model(), runtime = TaskServiceRuntime()
        runtime.model = value
        _ = await runtime.stopAfterSessionEnds(sessionAvailable: true)
        let ended = await runtime.stopAfterSessionEnds(sessionAvailable: true)
        XCTAssertFalse(ended)
        XCTAssertFalse(value.serviceStopping)
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
        XCTAssertEqual(value.workRequests.active.count, 1)
        XCTAssertEqual(value.manualWorkMode, .desk)
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

    func testFreshServiceInstanceInvalidatesStaleInterfaceHandle() async throws {
        let first = await model(), second = await model()
        let path = "/tmp/orxi-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await first.handleTaskControl($0) }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh(); await client.choose(.desk)
        let old = try XCTUnwrap(client.connectedServiceInstanceID)
        server.stop()
        for _ in 0..<100 where FileManager.default.fileExists(atPath: path) { try await Task.sleep(for: .milliseconds(10)) }
        let replacement = try LocalControlServer(path: path) { await second.handleTaskControl($0) }
        defer { replacement.stop() }
        await client.choose(.desk)
        XCTAssertTrue(client.verifiedWork, client.message)
        XCTAssertFalse(client.error, client.message)
        XCTAssertNotEqual(client.connectedServiceInstanceID, old)
        XCTAssertTrue(second.workRequests.active.isEmpty)
        await client.choose(.normal); await first.choose(.normal)
    }

    func testRegistrationReplyBindsHandleToServiceThatAcceptedIt() async throws {
        let first = await model(), second = await model()
        let router = ReplacingTaskService(first: first, second: second)
        let path = "/tmp/orxj-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await router.reply($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        await client.refresh(); await client.choose(.desk)
        XCTAssertTrue(client.verifiedWork, client.message)
        XCTAssertEqual(client.connectedServiceInstanceID, second.serviceInfo?.instanceID)
        XCTAssertNil(client.interfaceHandle)
        await client.refreshTaskService(renew: true)
        XCTAssertEqual(second.manualWorkMode, .desk)
        XCTAssertTrue(second.workRequests.active.isEmpty)
        await client.choose(.normal)
    }

    func testAutomaticRefreshAdoptsReplacementWithoutReplayingWork() async throws {
        let first = await model(), second = await model()
        let path = "/tmp/orxk-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await first.handleTaskControl($0) }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.normalBrightness, for: .desk)
        var prompts = 0
        client.requestUnlockedWorkPassword = { prompts += 1; throw ModeError("unexpected password prompt") }
        await client.refresh(); await client.choose(.desk)
        _ = try await first.registerWork(.init(title: "external command", source: "external"))
        server.stop()
        for _ in 0..<100 where FileManager.default.fileExists(atPath: path) { try await Task.sleep(for: .milliseconds(10)) }
        // A replacement publishes fresh state without replaying a previous intent.
        let replacement = try LocalControlServer(path: path) { await second.handleTaskControl($0) }
        defer { replacement.stop() }
        await client.refreshTaskService(renew: true)
        XCTAssertFalse(client.verifiedWork)
        XCTAssertFalse(client.error, client.message)
        XCTAssertTrue(second.workRequests.active.isEmpty)
        XCTAssertNil(second.manualWorkMode)
        XCTAssertEqual(prompts, 0)
        await client.choose(.normal); await first.choose(.normal)
    }

    func testMissingCoreIsRelaunchedWithoutAnotherPasswordPrompt() async throws {
        let first = await model(), second = await model()
        let path = "/tmp/orxn-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await first.handleTaskControl($0) }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh(); await client.choose(.desk)
        server.stop()
        for _ in 0..<100 where FileManager.default.fileExists(atPath: path) { try await Task.sleep(for: .milliseconds(10)) }
        var replacement: LocalControlServer?, launches = 0
        client.serviceRecoveryEnabled = true
        client.launchTaskService = { _, _ in
            launches += 1
            replacement = try LocalControlServer(path: path) { await second.handleTaskControl($0) }
            return second.taskControlReply()
        }
        defer { replacement?.stop() }
        await client.refreshTaskService(renew: true)
        XCTAssertEqual(launches, 1)
        XCTAssertFalse(client.verifiedWork)
        XCTAssertTrue(second.workRequests.active.isEmpty)
        await client.choose(.normal); await first.choose(.normal)
    }

    func testFailedCoreRestartBacksOffAndUserStopCancelsPendingRecovery() async throws {
        let client = await model(); client.isTaskService = false
        client.serviceSocket = "/tmp/orxo-" + UUID().uuidString.prefix(8) + "/control.sock"
        client.serviceRecoveryEnabled = true
        var launches = 0
        client.launchTaskService = { _, _ in launches += 1; throw ModeError("injected launch failure") }
        await client.refreshTaskService(); await client.refreshTaskService()
        XCTAssertEqual(launches, 1, "A failing service must not be launched every timer tick")
        XCTAssertTrue(client.error)
        client.manualWorkMode = .desk
        let replacement = await model()
        var server: LocalControlServer?
        client.serviceRetryAt = .distantPast
        client.launchTaskService = { _, _ in
            client.overrideWorkRequests(reason: "User stop during restart")
            server = try LocalControlServer(path: client.serviceSocket!) { await replacement.handleTaskControl($0) }
            return replacement.taskControlReply()
        }
        defer { server?.stop() }
        await client.refreshTaskService(renew: true)
        XCTAssertNil(client.legacyWorkMode)
        XCTAssertTrue(replacement.workRequests.active.isEmpty)
    }

    func testStaleRefreshCannotClearANewerAcceptedInterfaceBinding() async throws {
        let service = await model(), client = await model(), intercept = InterceptServiceReply()
        client.isTaskService = false
        let path = "/tmp/orxq-" + UUID().uuidString.prefix(8) + "/control.sock"
        let handle = WorkRequestHandle(), spec = WorkRequestSpec(title: "new interface", source: "interface", screen: .idle)
        let server = try LocalControlServer(path: path) { request in
            let reply = await service.handleTaskControl(request)
            if await intercept.take(request.operation) {
                _ = try? await service.registerWork(spec, handle: handle)
                await MainActor.run {
                    client.generation += 1
                    client.connectedServiceInstanceID = service.serviceInfo?.instanceID
                    client.interfaceHandle = handle; client.interfaceSpec = spec; client.manualWorkMode = .desk
                }
            }
            return reply
        }
        defer { server.stop() }
        client.serviceSocket = path; await client.refresh()
        await intercept.arm("status")
        await client.refreshTaskService(renew: true)
        XCTAssertEqual(client.interfaceHandle, handle)
        XCTAssertEqual(client.manualWorkMode, .desk)
        await service.choose(.normal)
    }

    func testSettingsGenerationChangeDoesNotStrandInterfaceBusyState() async throws {
        let service = await model(), client = await model(), intercept = InterceptServiceReply()
        client.isTaskService = false
        let path = "/tmp/orxw-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { request in
            let reply = await service.handleTaskControl(request)
            if await intercept.take(request.operation) {
                // A completed settings RPC advances generation but does not own
                // the work transition's busy state.
                await MainActor.run { client.generation += 1 }
            }
            return reply
        }
        defer { server.stop() }
        client.serviceSocket = path; client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh(); await intercept.arm("core-mode")
        await client.choose(.desk)
        XCTAssertFalse(client.busy)
        await client.choose(.desk)
        XCTAssertTrue(client.verifiedWork, client.message)
        await client.choose(.normal)
    }

    private func stopWhileInterfaceReplyAwaits(_ operation: String) async throws {
        let service = await model(), client = await model(), intercept = InterceptServiceReply()
        client.isTaskService = false
        let path = "/tmp/orxp-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { request in
            let reply = await service.handleTaskControl(request)
            if await intercept.take(request.operation) {
                await MainActor.run { client.overrideWorkRequests(reason: "User stopped during reply") }
                _ = await service.handleTaskControl(.init("stop-all"))
            }
            return reply
        }
        defer { server.stop() }
        client.serviceSocket = path; client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh(); client.manualWorkMode = .desk
        await intercept.arm(operation)
        await client.chooseThroughService(.desk, sleep: false, automatic: true, reconcilingRequests: true)
        XCTAssertTrue(service.workRequests.active.isEmpty, "A stop during recovery must remain stopped")
        XCTAssertNil(client.interfaceHandle)
        XCTAssertNil(client.legacyWorkMode)
    }
    func testStopDuringRecoveryPreflightDoesNotRegisterWorkAfterward() async throws { try await stopWhileInterfaceReplyAwaits("core-mode") }
    func testStopDuringAcceptedRegistrationDoesNotAdoptItsHandle() async throws { try await stopWhileInterfaceReplyAwaits("core-mode") }

    func testRemoteStopIsNotUndoneByAutomaticRefresh() async throws {
        let value = await model()
        let path = "/tmp/orxm-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        client.workScreen.select(.systemIdle, for: .desk)
        await client.refresh(); await client.choose(.desk)
        _ = await value.handleTaskControl(.init("stop-all"))
        await client.refreshTaskService(renew: true)
        await client.reconcileWorkRequests()
        XCTAssertNil(client.legacyWorkMode)
        XCTAssertNil(client.interfaceHandle)
        XCTAssertTrue(value.workRequests.active.isEmpty)
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
        XCTAssertEqual(value.manualWorkMode, .desk)
        var transitions: [Bool] = []
        let observation = client.$busy.dropFirst().sink { transitions.append($0) }
        defer { observation.cancel() }

        for _ in 0..<8 {
            await client.tick(battery: nil)
            XCTAssertTrue(client.verifiedWork)
            XCTAssertNil(client.interfaceHandle)
        }

        XCTAssertFalse(transitions.contains(true), "Heartbeat reconciliation must not show the mode-switching UI")
        XCTAssertTrue(value.workRequests.active.isEmpty)
        XCTAssertEqual(value.manualWorkMode, .desk)
    }

    func testInterfaceScreenChangeAndErrorRecoveryStillReconcile() async throws {
        let value = await model()
        let path = "/tmp/orxc-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await value.handleTaskControl($0) }
        defer { server.stop() }
        let client = await model(); client.isTaskService = false; client.serviceSocket = path
        await client.refresh(); await client.choose(.desk)
        await client.setWorkScreenBehavior(.normalBrightness)
        XCTAssertEqual(value.workScreen.ownBehavior(for: .desk), .normalBrightness)
        XCTAssertTrue(value.workRequests.active.isEmpty)
        XCTAssertTrue(client.verifiedWork)
        client.error = true
        await client.choose(.desk)
        XCTAssertFalse(client.error)
        XCTAssertTrue(client.verifiedWork)
        await client.choose(.normal)
    }

}
