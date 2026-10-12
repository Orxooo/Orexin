// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
import ServiceManagement
import WakeMacCore
import WakeMacPower
@testable import WakeMac

private actor LockRecoveryFailureLease: ScreenLockLeaseClient {
    var background = false
    func setBackground(_ enabled: Bool) { background = enabled }
    func renew() {}
    func prepareUnlockedWork() { XCTFail("This check must not ask for or alter password protection.") }
    func endUnlockedWork() throws { throw ModeError("injected helper recovery failure") }
    func power() -> String { "SleepDisabled \(background ? 1 : 0)" }
}

final class NativeBackendTests: XCTestCase {
    func testLiveKernelPowerReadbackMatchesPmset() throws {
        let text = try CommandRunner.run("/usr/bin/pmset", ["-g"], timeout: 5)
        let expected = try XCTUnwrap(SystemParsing.sleepDisabled(text))
        XCTAssertEqual(SystemPowerReadback.sleepDisabled(), expected)
    }
    func testPasswordRecoveryFailureStillReleasesBothPowerInhibitors() async throws {
        let suite = "RecoveryCleanup." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let lease = LockRecoveryFailureLease()
        let backend = MacBackend(command: { path, args, _ in
            if path.hasSuffix("sysadminctl") {
                if args.contains("immediate") { throw ModeError("injected local recovery failure") }
                return "screenLock delay is immediate"
            }
            return await lease.power()
        }, helper: lease, preferences: preferences)
        try await backend.configurePower(.background)
        preferences.set(true, forKey: "orexin.UnlockedLeaseArmed")
        do {
            try await backend.configurePower(.normal)
            XCTFail("Unconfirmed password recovery must be reported.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("injected local recovery failure")) }
        let snapshot = try await backend.snapshot()
        XCTAssertEqual(snapshot.idleSleepPrevented, false)
        XCTAssertEqual(snapshot.sleepDisabled, false)
        XCTAssertEqual(snapshot.backgroundLeaseActive, false)
        XCTAssertTrue(preferences.bool(forKey: "orexin.UnlockedLeaseArmed"))
    }
    func testDesktopAndNormalUseNativeAssertionsWithoutHelperApproval() async throws {
        let backend = MacBackend()
        let initial = try await backend.snapshot()
        guard initial.sleepDisabled == false else { throw XCTSkip("Another app is changing the global sleep switch.") }
        guard initial.lockPolicy == .immediate else { throw XCTSkip("Runtime check requires existing immediate lock protection.") }
        do {
            try await backend.configurePower(.desk)
            let desk = try await backend.snapshot()
            XCTAssertTrue(desk.matches(.desk))
            try await backend.configurePower(.normal)
            let normal = try await backend.snapshot()
            XCTAssertTrue(normal.matches(.normal))
        } catch {
            try? await backend.configurePower(.normal)
            throw error
        }
    }
    func testUnapprovedBackgroundFailsAndRestoresNormal() async throws {
        guard SMAppService.daemon(plistName: PowerService.plistName).status != .enabled else {
            throw XCTSkip("This check must not alter an approved helper's global power setting.")
        }
        let backend = MacBackend()
        let initial = try await backend.snapshot()
        guard initial.sleepDisabled == false, initial.lockPolicy == .immediate else {
            throw XCTSkip("Existing power state is unsuitable for a nonprivileged runtime check.")
        }
        let result = await ModeCoordinator(backend: backend).select(.background)
        guard case .failed = result else { return XCTFail("Unapproved helper must not activate background mode.") }
        let final = try await backend.snapshot()
        XCTAssertTrue(final.matches(.normal))
    }
}
