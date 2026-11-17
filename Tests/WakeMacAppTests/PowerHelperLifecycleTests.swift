// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import WakeMac

final class PowerHelperLifecycleTests: XCTestCase {
    func testRegistrationWaitsForOldServiceToRetire() async throws {
        var attempts = 0
        var waits: [UInt64] = []
        try await PowerHelperLifecycle.registerAfterUnregister(register: {
            attempts += 1
            if attempts < 3 { throw NSError(domain: NSPOSIXErrorDomain, code: 1) }
        }, approvalRequired: { false }, wait: { waits.append($0) })
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(waits, [250_000_000, 500_000_000])
    }
    func testRegistrationFailureIsBounded() async {
        var attempts = 0
        do {
            try await PowerHelperLifecycle.registerAfterUnregister(register: {
                attempts += 1; throw NSError(domain: NSPOSIXErrorDomain, code: 1)
            }, approvalRequired: { false }, wait: { _ in })
            XCTFail("Registration must fail")
        } catch { XCTAssertEqual((error as NSError).code, 1) }
        XCTAssertEqual(attempts, 5)
    }
    func testApprovalRequirementDoesNotRetry() async {
        var attempts = 0
        do {
            try await PowerHelperLifecycle.registerAfterUnregister(register: {
                attempts += 1; throw NSError(domain: NSPOSIXErrorDomain, code: 1)
            }, approvalRequired: { true }, wait: { _ in XCTFail("Must await user approval") })
            XCTFail("Registration must fail")
        } catch {}
        XCTAssertEqual(attempts, 1)
    }
}
