// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
@testable import WakeMac
import WakeMacCore

private actor HeartbeatLease: BackgroundLeaseClient {
    var disabled = false
    var renewals = 0
    var lastRenewal = ProcessInfo.processInfo.systemUptime
    var failNext = false
    var connectionFailure = false
    var starts = 0
    var pending = false
    var replyDelay: Double = 0
    var repairsExternalReset = false
    func setBackground(_ enabled: Bool) async throws { disabled = enabled; if enabled { starts += 1 }; lastRenewal = ProcessInfo.processInfo.systemUptime }
    func renew() async throws {
        pending = true
        if replyDelay > 0 {
            let delay = replyDelay
            await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + delay) { continuation.resume() } }
        }
        pending = false
        if connectionFailure { connectionFailure = false; disabled = false; throw PowerHelperConnectionFailure(reason: "injected transport interruption") }
        if failNext { disabled = false; throw ModeError("injected connection loss") }
        if !disabled && repairsExternalReset { disabled = true }
        guard disabled else { throw ModeError("lease ended") }
        renewals += 1; lastRenewal = ProcessInfo.processInfo.systemUptime
    }
    func interruptConnection() { connectionFailure = true }
    func configureFailure() { failNext = true }
    func configureDelay(_ seconds: Double) { replyDelay = seconds }
    func resetExternally() { disabled = false; repairsExternalReset = true }
    func power() -> String { "SleepDisabled \(disabled ? 1 : 0)" }
    func fresh(ttl: Double) -> Bool { disabled && ProcessInfo.processInfo.systemUptime - lastRenewal < ttl }
}

final class HeartbeatTests: XCTestCase {
    func testInitialPowerReadDoesNotStarveLeaseRenewal() async throws {
        let lease = HeartbeatLease()
        let backend = MacBackend(command: { path, _, _ in
            if path.hasSuffix("sysadminctl") { return "screenLock delay is immediate" }
            try await Task.sleep(nanoseconds: 300_000_000)
            return await lease.power()
        }, helper: lease, heartbeatInterval: 20_000_000)
        try await backend.configurePower(.background)
        let fresh = await lease.fresh(ttl: 0.15), renewals = await lease.renewals
        XCTAssertTrue(fresh); XCTAssertGreaterThanOrEqual(renewals, 3)
        try await backend.configurePower(.normal)
    }
    private func backend(_ lease: HeartbeatLease, readDelay: UInt64 = 0) -> MacBackend {
        MacBackend(command: { path, _, _ in
            if path.hasSuffix("sysadminctl") { if readDelay > 0 { try await Task.sleep(nanoseconds: readDelay) }; return "screenLock delay is immediate" }
            return await lease.power()
        }, helper: lease, heartbeatInterval: 20_000_000)
    }
    func testSlowSnapshotDoesNotStarveLeaseRenewalAndNormalStopsIt() async throws {
        let lease = HeartbeatLease(), backend = backend(lease, readDelay: 300_000_000)
        try await backend.configurePower(.background)
        let snapshot = try await backend.snapshot()
        XCTAssertTrue(snapshot.matches(.background))
        let fresh = await lease.fresh(ttl: 0.15), renewals = await lease.renewals
        XCTAssertTrue(fresh); XCTAssertGreaterThanOrEqual(renewals, 3)
        try await backend.configurePower(.normal)
        let stopped = await lease.renewals
        try await Task.sleep(nanoseconds: 100_000_000)
        let after = await lease.renewals, disabled = await lease.disabled
        XCTAssertEqual(after, stopped); XCTAssertFalse(disabled)
    }
    func testTransportInterruptionReacquiresApprovedBackgroundLeaseWithoutAuthorization() async throws {
        let lease = HeartbeatLease(), backend = backend(lease)
        try await backend.configurePower(.background)
        await lease.interruptConnection()
        for _ in 0..<100 where await lease.starts < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        let snapshot = try await backend.snapshot(), starts = await lease.starts
        XCTAssertEqual(starts, 2); XCTAssertTrue(snapshot.matches(.background))
        try await backend.configurePower(.normal)
    }

    func testSnapshotRepairsExternalResetBeforeReportingBackgroundState() async throws {
        let lease = HeartbeatLease()
        let backend = MacBackend(command: { path, _, _ in
            if path.hasSuffix("sysadminctl") { return "screenLock delay is immediate" }
            return await lease.power()
        }, helper: lease, heartbeatInterval: 60_000_000_000)
        try await backend.configurePower(.background)
        await lease.resetExternally()
        let state = try await backend.snapshot()
        XCTAssertTrue(state.matches(.background))
        try await backend.configurePower(.normal)
    }

    @MainActor func testExternalResetDoesNotEndRunningSession() async throws {
        let lease = HeartbeatLease(), prefs = UserDefaults(suiteName: "PrioritySession." + UUID().uuidString)!
        let backend = MacBackend(command: { path, _, _ in
            if path.hasSuffix("sysadminctl") { return "screenLock delay is immediate" }
            return await lease.power()
        }, helper: lease, heartbeatInterval: 60_000_000_000, preferences: prefs)
        let model = AppModel(backend: backend, preferences: prefs, sessionEffects: IndependentCoreTests.Effects())
        model.workScreen = WorkScreenPolicy(preferences: prefs, runtimeEnabled: false)
        model.thermalStateProvider = { .nominal }; model.isTaskService = true
        model.sessions.defaultMode = .background
        await model.sessions.start()
        XCTAssertTrue(model.sessions.isActive)
        await lease.resetExternally()
        await model.refresh()
        await model.sessions.tick(now: Date())
        XCTAssertTrue(model.sessions.isActive)
        XCTAssertEqual(model.active, .background)
        await model.sessions.end()
    }

    func testRenewalFailureReleasesNativeAssertionAndKeepsNestedErrorUntilExplicitRecovery() async throws {
        let lease = HeartbeatLease(), backend = backend(lease)
        try await backend.configurePower(.background); await lease.configureFailure()
        try await Task.sleep(nanoseconds: 100_000_000)
        do { _ = try await backend.snapshot(); XCTFail("failure hidden") }
        catch { XCTAssertTrue(error.localizedDescription.contains("injected connection loss")) }
        try await backend.configurePower(.normal)
        let final = try await backend.snapshot(); XCTAssertTrue(final.matches(.normal))
    }
    func testNormalDrainsInFlightReplyBeforeStartingAnotherMode() async throws {
        let lease = HeartbeatLease(), backend = backend(lease)
        await lease.configureDelay(0.08)
        try await backend.configurePower(.background)
        for _ in 0..<100 {
            if await lease.pending { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let wasPending = await lease.pending; XCTAssertTrue(wasPending)
        try await backend.configurePower(.normal)
        try await backend.configurePower(.desk)
        try await Task.sleep(nanoseconds: 120_000_000)
        let desk = try await backend.snapshot(); XCTAssertTrue(desk.matches(.desk))
        let disabled = await lease.disabled; XCTAssertFalse(disabled)
        try await backend.configurePower(.normal)
    }
}
