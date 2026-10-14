import XCTest
@testable import WakeMacCore

final class WorkRequestTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testOverlappingCompletionNeverReleasesAnotherRequestAndTearsDownOnce() throws {
        var ledger = WorkRequestLedger()
        let a = try ledger.register(.init(title: "build", mode: .desk, screen: .awake, teardown: .sleepOnSuccess), now: now)
        let b = try ledger.register(.init(title: "backup", mode: .background, screen: .idle), now: now)
        XCTAssertEqual(ledger.demand?.mode, .background)
        XCTAssertEqual(ledger.demand?.screen, .awake)
        XCTAssertNil(try ledger.complete(a, exitCode: 0, now: now))
        XCTAssertEqual(ledger.active.count, 1)
        XCTAssertEqual(ledger.demand?.screen, .idle)
        XCTAssertEqual(try ledger.complete(b, exitCode: 0, now: now), .sleepOnSuccess)
        XCTAssertNil(ledger.demand)
        XCTAssertNil(try ledger.complete(b, exitCode: 0, now: now))
    }
    func testFailureAndExpiryVetoAutomaticSleep() throws {
        for failure in [true, false] {
            var ledger = WorkRequestLedger()
            let a = try ledger.register(.init(title: "build", teardown: .sleepOnSuccess), now: now)
            let b = try ledger.register(.init(title: "leased", leaseSeconds: 5), now: now)
            if failure { _ = try ledger.complete(b, exitCode: 9, now: now) }
            else { _ = ledger.reap(now: now.addingTimeInterval(6), processAlive: { _ in true }) }
            XCTAssertEqual(try ledger.complete(a, exitCode: 0, now: now.addingTimeInterval(7)), .restore)
            XCTAssertEqual(ledger.records.first { $0.id == b.id }?.state, failure ? .failed : .expired)
        }
    }
    func testStopAllAndLateCallbacksCannotResurrectRequests() throws {
        var ledger = WorkRequestLedger()
        let handle = try ledger.register(.init(title: "task", leaseSeconds: 5, teardown: .sleepOnSuccess), now: now)
        ledger.stopAll(reason: "user", now: now)
        XCTAssertThrowsError(try ledger.heartbeat(handle, now: now))
        XCTAssertNil(try ledger.complete(handle, exitCode: 0, now: now))
        XCTAssertEqual(ledger.records[0].state, .overridden)
        XCTAssertEqual(ledger.records[0].exitCode, 0)
        XCTAssertNil(ledger.demand)
    }
    func testIdentityOwnershipAndDeadlineBoundHeartbeat() throws {
        var ledger = WorkRequestLedger()
        let handle = try ledger.register(.init(title: "task", deadline: now.addingTimeInterval(8), leaseSeconds: 5), now: now)
        XCTAssertThrowsError(try ledger.complete(.init(id: handle.id, token: UUID()), exitCode: 0, now: now))
        try ledger.heartbeat(handle, now: now.addingTimeInterval(4))
        XCTAssertNil(ledger.reap(now: now.addingTimeInterval(7), processAlive: { _ in true }))
        XCTAssertEqual(ledger.reap(now: now.addingTimeInterval(8), processAlive: { _ in true }), .restore)
        XCTAssertThrowsError(try ledger.heartbeat(handle, now: now.addingTimeInterval(9)))
    }
    func testProcessLossIsNotSuccessAndRestartNeverReplays() throws {
        var ledger = WorkRequestLedger()
        let identity = try XCTUnwrap(LocalProcessIdentity.capture(pid: Int32(ProcessInfo.processInfo.processIdentifier)))
        let handle = try ledger.register(.init(title: "task", process: identity, teardown: .sleepOnSuccess), now: now)
        XCTAssertEqual(ledger.reap(now: now, processAlive: { _ in false }), .restore)
        XCTAssertEqual(ledger.records[0].state, .lost)
        XCTAssertNil(try ledger.complete(handle, exitCode: 0, now: now))
        XCTAssertEqual(ledger.records[0].state, .lost)
        XCTAssertEqual(ledger.records[0].exitCode, 0)
        var live = WorkRequestLedger()
        _ = try live.register(.init(title: "other"), now: now)
        let recovered = WorkRequestLedger(recovering: live.records, now: now)
        XCTAssertEqual(recovered.records[0].state, .lost)
        XCTAssertTrue(recovered.active.isEmpty)
    }
    func testRegistrationIsIdempotentAndCannotChangeAnExistingRequest() throws {
        var ledger = WorkRequestLedger()
        let handle = WorkRequestHandle(id: UUID(), token: UUID())
        let spec = WorkRequestSpec(title: "task", leaseSeconds: 30)
        _ = try ledger.register(spec, handle: handle, now: now)
        _ = try ledger.register(spec, handle: handle, now: now)
        XCTAssertEqual(ledger.active.count, 1)
        XCTAssertThrowsError(try ledger.register(.init(title: "different"), handle: handle, now: now))
        XCTAssertThrowsError(try ledger.register(.init(title: "", leaseSeconds: -1), now: now))
    }
}
