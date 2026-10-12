// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMacCore

private final class LockRecovery: ScreenLockRecoverySwitch {
    var immediate = true
    var armed = false
    var failed = false
    var restores = 0
    func isImmediate(userID: UInt32) throws -> Bool { immediate }
    func armRecovery(userID: UInt32, seconds: TimeInterval) throws { armed = true }
    func restoreImmediate(userID: UInt32) throws {
        if failed { throw ModeError("failed") }
        restores += 1; immediate = true; armed = false
    }
}

final class ScreenLockLeaseTests: XCTestCase {
    func testDisconnectWaitsForAuthenticationThenRestores() throws {
        let recovery = LockRecovery(), owner = UUID()
        let lease = ScreenLockLease(recovery: recovery)
        try lease.begin(owner: owner, userID: 501, uptime: 100)
        lease.abandon(owner: owner, uptime: 105)
        recovery.immediate = false
        try lease.expire(uptime: 114); XCTAssertFalse(recovery.immediate)
        try lease.expire(uptime: 115); XCTAssertTrue(recovery.immediate)
    }
    func testUnlockedWorkMustVerifyOffButNormalMustReleaseInhibitors() {
        var snapshot = Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: true, displaySleepAllowed: true, backgroundLeaseActive: false)
        XCTAssertTrue(LockRequirement.unlockedWork.accepts(.immediate))
        XCTAssertFalse(snapshot.matches(.desk, lockRequirement: .unlockedWork))
        snapshot.lockPolicy = .off
        XCTAssertTrue(snapshot.matches(.desk, lockRequirement: .unlockedWork))
        XCTAssertFalse(snapshot.matches(.normal, lockRequirement: .unlockedWork))
        snapshot.idleSleepPrevented = false; snapshot.lockPolicy = .immediate
        XCTAssertTrue(snapshot.matches(.normal, lockRequirement: .unlockedWork))
    }
    func testRecoveryIsArmedBeforeAuthenticationAndExpires() throws {
        let recovery = LockRecovery(), owner = UUID()
        let lease = ScreenLockLease(recovery: recovery)
        try lease.begin(owner: owner, userID: 501, uptime: 100)
        XCTAssertTrue(recovery.armed); XCTAssertTrue(recovery.immediate)
        recovery.immediate = false
        try lease.expire(uptime: 129); XCTAssertFalse(recovery.immediate)
        try lease.expire(uptime: 130); XCTAssertTrue(recovery.immediate)
        XCTAssertFalse(lease.owns(owner))
    }
    func testRenewalAndModeChangeReuseTheSameLease() throws {
        let recovery = LockRecovery(), owner = UUID()
        let lease = ScreenLockLease(recovery: recovery)
        try lease.begin(owner: owner, userID: 501, uptime: 100)
        recovery.immediate = false
        try lease.begin(owner: owner, userID: 501, uptime: 120)
        try lease.expire(uptime: 140); XCTAssertFalse(recovery.immediate)
        try lease.end(owner: owner); XCTAssertTrue(recovery.immediate)
    }
    func testFailedRestoreKeepsOwnershipForRetry() throws {
        let recovery = LockRecovery(), owner = UUID()
        let lease = ScreenLockLease(recovery: recovery)
        try lease.begin(owner: owner, userID: 501, uptime: 100)
        recovery.immediate = false; recovery.failed = true
        XCTAssertThrowsError(try lease.end(owner: owner)); XCTAssertTrue(lease.owns(owner))
        recovery.failed = false
        try lease.expire(uptime: 130); XCTAssertTrue(recovery.immediate)
    }
    func testCannotAdoptOtherUserOrPreexistingUnlockedPolicy() throws {
        let recovery = LockRecovery(), owner = UUID()
        let lease = ScreenLockLease(recovery: recovery)
        recovery.immediate = false
        XCTAssertThrowsError(try lease.begin(owner: owner, userID: 501, uptime: 100))
        XCTAssertFalse(recovery.armed)
        recovery.immediate = true
        XCTAssertThrowsError(try lease.begin(owner: owner, userID: 0, uptime: 100))
        try lease.begin(owner: owner, userID: 501, uptime: 100)
        XCTAssertThrowsError(try lease.begin(owner: UUID(), userID: 502, uptime: 110))
        try lease.end(owner: UUID()); XCTAssertEqual(recovery.restores, 0)
    }
}
