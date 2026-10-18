import XCTest
@testable import WakeMacCore

final class WorkProfileTests: XCTestCase {
    func testProfileResolutionPreservesOwnershipAndBoundsDeadline() throws {
        var profile = WorkProfile(name: "Build")
        profile.mode = .background; profile.screen = .awake; profile.timeoutSeconds = 20
        profile.success.teardown = .sleepOnSuccess
        let now = Date(timeIntervalSince1970: 100)
        let spec = WorkRequestSpec(title: "job", leaseSeconds: 60, profileID: profile.id)
        let result = try profile.applying(to: spec, now: now)
        XCTAssertEqual(result.mode, .background); XCTAssertEqual(result.screen, .awake)
        XCTAssertEqual(result.deadline, now.addingTimeInterval(20))
        XCTAssertEqual(result.leaseSeconds, 60); XCTAssertEqual(result.profileID, profile.id)
        XCTAssertEqual(result.teardown, .sleepOnSuccess)
    }
    func testInvalidProfilesAndLegacyRequestDecoding() throws {
        var profile = WorkProfile(name: "Build")
        profile.failure.teardown = .sleepOnSuccess
        XCTAssertNotNil(profile.validationError)
        profile.failure.teardown = .restore; profile.timeoutSeconds = .infinity
        XCTAssertNotNil(profile.validationError)
        profile.timeoutSeconds = nil; profile.success.scriptPath = "relative.sh"
        XCTAssertNotNil(profile.validationError)
        let old = Data(#"{"title":"legacy","source":"external","mode":"desk","screen":"idle","teardown":"restore"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(WorkRequestSpec.self, from: old).profileID)
    }
    func testOnlySuccessFailureAndTimeoutHaveConfiguredOutcomes() {
        let profile = WorkProfile(name: "Build")
        for state in [RequestState.overridden, .lost, .cancelled, .rejected, .active] {
            XCTAssertNil(profile.outcome(for: state))
        }
        XCTAssertNotNil(profile.outcome(for: .expired))
    }
}
