import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor final class ConcurrentRequestTests: XCTestCase {
    private final class Effects: SessionEffectManaging {
        var canAcquire = true
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport {
            .init(displayAssertionActive: canAcquire && working && choices.preventDisplaySleep)
        }
        func release() {}
    }
    func fixture() -> (AppModel, AutomationBackend) {
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "Concurrent." + UUID().uuidString)!, sessionEffects: Effects())
        model.thermalStateProvider = { .nominal }
        return (model, backend)
    }
    func testTwoRequestsCompleteIndependentlyAndRestoreOnlyAfterLast() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal)
        let a = try await model.registerWork(.init(title: "build", screen: .awake))
        let b = try await model.registerWork(.init(title: "backup", mode: .background))
        XCTAssertEqual(model.active, .background)
        try await model.completeWork(a, exitCode: 0)
        XCTAssertEqual(model.active, .background)
        XCTAssertEqual(model.workRequests.active.count, 1)
        try await model.completeWork(b, exitCode: 0)
        XCTAssertEqual(model.active, .normal)
        let changes = await backend.changes
        try await model.completeWork(b, exitCode: 0)
        let afterDuplicate = await backend.changes
        XCTAssertEqual(changes, afterDuplicate)
    }
    func testSessionEndingAndRequestEndingPreserveEachOthersOwnership() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal)
        model.sessions.endCondition = .duration; model.sessions.durationMinutes = 1
        let now = Date()
        await model.sessions.start(now: now)
        let a = try await model.registerWork(.init(title: "backup"))
        await model.sessions.tick(now: now.addingTimeInterval(61))
        XCTAssertTrue(model.verifiedWork)
        var sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0)
        try await model.completeWork(a, exitCode: 0)
        XCTAssertEqual(model.active, .normal)
        sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 0) // external default only restores; no forced sleep

        await model.sessions.start()
        let b = try await model.registerWork(.init(title: "other"))
        try await model.completeWork(b, exitCode: 0)
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertTrue(model.verifiedWork)
        await model.sessions.end()
    }
    func testManualNormalOverridesTasksAndLateCompletionCannotScheduleSleep() async throws {
        let (model, _) = fixture()
        await model.choose(.normal)
        let a = try await model.registerWork(.init(title: "build", teardown: .sleepOnSuccess))
        await model.choose(.normal)
        try await model.completeWork(a, exitCode: 0)
        XCTAssertEqual(model.workRequests.records.first?.state, .overridden)
        XCTAssertNil(model.automation.jobSleepAt)
        XCTAssertEqual(model.active, .normal)
    }
    func testFinalSuccessCountdownCannotInterruptNewRequestOrManualOwner() async throws {
        let (model, _) = fixture()
        await model.choose(.normal)
        let a = try await model.registerWork(.init(title: "build", teardown: .sleepOnSuccess))
        try await model.completeWork(a, exitCode: 0)
        XCTAssertNotNil(model.automation.jobSleepAt)
        let b = try await model.registerWork(.init(title: "new"))
        XCTAssertNil(model.automation.jobSleepAt)
        await model.choose(.desk)
        try await model.completeWork(b, exitCode: 0)
        XCTAssertTrue(model.verifiedWork)
        await model.choose(.normal)
    }
    func testThermalOverrideAndLeaseExpiryReleaseWithoutSuccessfulCompletion() async throws {
        let (model, _) = fixture()
        await model.choose(.normal)
        let now = Date()
        let a = try await model.registerWork(.init(title: "leased", leaseSeconds: 5), now: now)
        await model.reapWorkRequests(now: now.addingTimeInterval(6))
        XCTAssertEqual(model.active, .normal)
        XCTAssertEqual(model.workRequests.records.first { $0.id == a.id }?.state, .expired)
        let b = try await model.registerWork(.init(title: "hot"))
        model.thermalStateProvider = { .critical }
        await model.protectFromThermalPressure()
        XCTAssertEqual(model.active, .normal)
        XCTAssertEqual(model.workRequests.records.first { $0.id == b.id }?.state, .overridden)
    }
    func testConcurrentCommandsUseActualIndependentExitCodes() async throws {
        let (model, _) = fixture()
        await model.choose(.normal)
        let a = Task { await model.startJob(command: "/bin/sleep 0.2; exit 0", directory: "/tmp") }
        while model.workRequests.active.isEmpty { await Task.yield() }
        let b = Task { await model.startJob(command: "/bin/sleep 0.5; exit 7", directory: "/tmp") }
        await a.value
        XCTAssertTrue(model.jobRunning)
        XCTAssertEqual(model.workRequests.active.count, 1)
        XCTAssertNil(model.automation.jobSleepAt)
        await b.value
        XCTAssertFalse(model.jobRunning)
        XCTAssertEqual(Set(model.workRequests.records.compactMap(\.exitCode)), [0, 7])
        XCTAssertNil(model.automation.jobSleepAt)
        XCTAssertEqual(model.active, .normal)
    }
    func testVisibleCountdownCancellationReleasesLastRequestHold() async throws {
        let (model, _) = fixture()
        await model.choose(.normal)
        let handle = try await model.registerWork(.init(title: "done", teardown: .sleepOnSuccess))
        try await model.completeWork(handle, exitCode: 0)
        XCTAssertNotNil(model.requestCountdownMode)
        model.cancelVisibleCountdown()
        await model.reconcileWorkRequests()
        XCTAssertNil(model.requestCountdownMode); XCTAssertNil(model.automation.jobSleepAt)
        XCTAssertEqual(model.active, .normal)
    }
    func testStopAllDuringNativeActivationWinsOverLateRegistration() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal)
        await backend.holdPower()
        let registration = Task { try await model.registerWork(.init(title: "delayed")) }
        while await !backend.isWaiting { await Task.yield() }
        await model.choose(.normal)
        await backend.release()
        do { _ = try await registration.value; XCTFail("Stopped registration must not succeed") } catch {}
        XCTAssertTrue(model.workRequests.active.isEmpty)
        XCTAssertEqual(model.active, .normal)
        XCTAssertEqual(model.workRequests.records.first?.state, .overridden)
    }
    func testBatteryAndChangedLockPolicyOverrideLiveRequests() async throws {
        for battery in [true, false] {
            let (model, backend) = fixture()
            await model.choose(.normal)
            _ = try await model.registerWork(.init(title: "protected"))
            if battery {
                let now = Date()
                await model.tick(now: now, battery: .init(percent: 10, onBattery: true))
                await model.tick(now: now.addingTimeInterval(61), battery: .init(percent: 10, onBattery: true))
            } else {
                await backend.removeLock(); await model.refresh()
            }
            XCTAssertTrue(model.workRequests.active.isEmpty)
            XCTAssertEqual(model.workRequests.records.last?.state, .overridden)
        }
    }
    func testDisplayAcquisitionFailureIsNotReportedAsSatisfied() async throws {
        let effects = Effects(); effects.canAcquire = false
        let model = AppModel(backend: AutomationBackend(), preferences: UserDefaults(suiteName: "DisplayFailure." + UUID().uuidString)!, sessionEffects: effects)
        await model.choose(.normal)
        do { _ = try await model.registerWork(.init(title: "UI task", screen: .awake)); XCTFail("No display assertion acquired") } catch {}
        XCTAssertEqual(model.workRequests.records.last?.state, .rejected)
        XCTAssertEqual(model.active, .normal)
    }

    func testNewRegistrationCannotCancelBatteryTeardownInFlight() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal)
        _ = try await model.registerWork(.init(title: "battery task"))
        let now = Date()
        await model.tick(now: now, battery: .init(percent: 10, onBattery: true))
        await backend.holdPower()
        let teardown = Task { await model.tick(now: now.addingTimeInterval(61), battery: .init(percent: 10, onBattery: true)) }
        while await !backend.isWaiting { await Task.yield() }
        do { _ = try await model.registerWork(.init(title: "late arrival")); XCTFail("Safety cleanup must reject arrivals") } catch {}
        await backend.release(); await teardown.value
        let sleeps = await backend.sleeps
        XCTAssertEqual(sleeps, 1); XCTAssertEqual(model.active, .normal)
        XCTAssertTrue(model.workRequests.active.isEmpty)
    }
    func testDeadlineElapsedDuringNativeActivationRejectsRegistration() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal); await backend.holdPower()
        let registration = Task { try await model.registerWork(.init(title: "short", deadline: Date().addingTimeInterval(0.05))) }
        while await !backend.isWaiting { await Task.yield() }
        try await Task.sleep(for: .milliseconds(80))
        await backend.release()
        do { _ = try await registration.value; XCTFail("Expired activation cannot succeed") } catch {}
        XCTAssertEqual(model.workRequests.records.last?.state, .expired)
        XCTAssertEqual(model.active, .normal)
    }
    func testRepeatedDeskRuleAndBackgroundTaskPreserveRuleScreenPolicy() async throws {
        let observation = RequestObservations()
        let backend = AutomationBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "RequestRule." + UUID().uuidString)!, triggerSource: observation, sessionEffects: Effects())
        await model.choose(.normal, automatic: true, startupRecovery: true)
        var rule = TriggerRule(name: "display", enabled: true, conditions: [.init(kind: .externalDisplay)])
        rule.preventDisplaySleep = false; model.triggers.save(rule)
        let now = Date()
        await model.tickFeatures(now: now, battery: nil)
        let handle = try await model.registerWork(.init(title: "background", mode: .background))
        let before = await backend.changes
        await model.tickFeatures(now: now.addingTimeInterval(6), battery: nil)
        let after = await backend.changes
        XCTAssertEqual(before, after)
        XCTAssertEqual(model.workScreen.behavior(for: .background), .systemIdle)
        observation.connected = false
        await model.tickFeatures(now: now.addingTimeInterval(12), battery: nil)
        XCTAssertEqual(model.active, .background)
        try await model.completeWork(handle, exitCode: 0)
        XCTAssertEqual(model.active, .normal)
    }
    func testStopAllDuringSocketPreflightRejectsOlderRegistration() async throws {
        let backend = SnapshotGateBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "PreflightStop." + UUID().uuidString)!, sessionEffects: Effects())
        await model.choose(.normal)
        await backend.holdNextSnapshot()
        let request = Task { await model.handleTaskControl(.init("register", handle: .init(), spec: .init(title: "preflight"))) }
        while await !backend.isWaiting { await Task.yield() }
        await model.choose(.normal)
        await backend.release(); let result = await request.value
        XCTAssertFalse(result.ok)
        XCTAssertTrue(model.workRequests.active.isEmpty); XCTAssertEqual(model.active, .normal)
    }

    func testStopAllDuringRegistrationReapRejectsOlderArrival() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal)
        _ = try await model.registerWork(.init(title: "expiring", deadline: Date().addingTimeInterval(0.05)))
        try await Task.sleep(for: .milliseconds(80))
        await backend.holdPower()
        let registration = Task { await model.handleTaskControl(.init("register", handle: .init(), spec: .init(title: "old arrival"))) }
        while await !backend.isWaiting { await Task.yield() }
        await model.choose(.normal)
        await backend.release()
        let result = await registration.value
        XCTAssertFalse(result.ok); XCTAssertTrue(model.workRequests.active.isEmpty)
        XCTAssertEqual(model.active, .normal)
    }
    func testOwnerExitingDuringActivationCannotBeAcknowledged() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal); await backend.holdPower()
        let owner = Process(); owner.executableURL = URL(fileURLWithPath: "/bin/sleep"); owner.arguments = ["0.1"]
        try owner.run()
        let identity = try XCTUnwrap(LocalProcessIdentity.capture(pid: owner.processIdentifier))
        let registration = Task { try await model.registerWork(.init(title: "lost reporter", process: identity)) }
        while await !backend.isWaiting { await Task.yield() }
        while owner.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        await backend.release()
        do { _ = try await registration.value; XCTFail("Lost owner cannot be acknowledged") } catch {}
        XCTAssertEqual(model.workRequests.records.last?.state, .lost)
        XCTAssertEqual(model.active, .normal)
    }
    func testCancelledRegistrationReleasesOnlyItsOwnRequestAfterActivation() async throws {
        let (model, backend) = fixture()
        await model.choose(.normal)
        let existing = try await model.registerWork(.init(title: "existing desk"))
        await backend.holdPower()
        let registration = Task { try await model.registerWork(.init(title: "cancelled background", mode: .background)) }
        while await !backend.isWaiting { await Task.yield() }
        registration.cancel(); await backend.release()
        do { _ = try await registration.value; XCTFail("Cancelled request cannot be acknowledged") } catch {}
        XCTAssertEqual(model.workRequests.active.map(\.id), [existing.id])
        XCTAssertEqual(model.workRequests.records.last?.state, .cancelled)
        XCTAssertEqual(model.active, .desk)
        try await model.completeWork(existing, exitCode: 0)
    }
    func testStopAllReportsNativeCleanupFailure() async throws {
        let backend = SnapshotGateBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "StopFailure." + UUID().uuidString)!, sessionEffects: Effects())
        _ = try await model.registerWork(.init(title: "task"))
        await backend.failCleanup()
        let result = await model.handleTaskControl(.init("stop-all"))
        XCTAssertFalse(result.ok); XCTAssertNotNil(result.error)
        XCTAssertEqual(result.tasks.first?.request.state, .overridden)
    }

}

@MainActor private final class RequestObservations: TriggerObservationSource {
    var connected = true
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
        var snapshot = TriggerSnapshot(); snapshot.externalDisplay = connected; return snapshot
    }
}
private actor SnapshotGateBackend: ModeBackend {
    var mode: WorkMode = .normal
    var hold = false
    var rejectNormal = false
    func failCleanup() { rejectNormal = true }
    var gate: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { gate != nil }
    func holdNextSnapshot() { hold = true }
    func release() { gate?.resume(); gate = nil }
    func snapshot() async throws -> Snapshot {
        if hold { hold = false; await withCheckedContinuation { gate = $0 } }
        return Snapshot(sleepDisabled: mode == .background, lockPolicy: .immediate, idleSleepPrevented: mode != .normal, displaySleepAllowed: true, backgroundLeaseActive: mode == .background)
    }
    func configurePower(_ mode: WorkMode) async throws {
        if mode == .normal && rejectNormal { throw ModeError("Simulated native release failure") }
        self.mode = mode
    }
    func requestLockPolicy(_ policy: LockPolicy) async {}
    func sleepNow() async throws {}
}
