import XCTest
@testable import WakeMac

@MainActor final class UpdateMonitorTests: XCTestCase {
    private func release(_ tag: String, preview: Bool = false, repository: String = "Orxooo/Orexin") -> GitHubRelease {
        .init(tagName: tag, htmlURL: "https://github.com/\(repository)/releases/tag/\(tag)", draft: false, prerelease: preview)
    }
    func testNewVersionAnnouncedOnceAcrossChecksAndRestart() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notices = ClientNoticeCenter(preferences: defaults)
        let release = release("v1.0.3")
        let monitor = UpdateMonitor(notices: notices, preferences: defaults, current: "v1.0.2", previews: false, loader: { [release] })
        await monitor.check(manual: true); await monitor.check(manual: true)
        XCTAssertEqual(notices.entries.filter { $0.kind == .update }.count, 1)
        XCTAssertEqual(monitor.releaseURL, release.url)
        let newInbox = ClientNoticeCenter(preferences: defaults)
        let restarted = UpdateMonitor(notices: newInbox, preferences: defaults, current: "v1.0.2", loader: { [release] })
        await restarted.check(manual: true)
        XCTAssertTrue(newInbox.entries.isEmpty)
    }
    func testAutomaticChecksAreThrottledAndOfflineFailureDoesNotPopup() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notices = ClientNoticeCenter(preferences: defaults)
        var requests = 0
        let monitor = UpdateMonitor(notices: notices, preferences: defaults, current: "v1.0.2", loader: {
            requests += 1; throw URLError(.notConnectedToInternet)
        })
        let now = Date()
        await monitor.check(now: now)
        await monitor.check(now: now.addingTimeInterval(60))
        XCTAssertEqual(requests, 1); XCTAssertTrue(notices.entries.isEmpty)
        await monitor.check(manual: true, now: now.addingTimeInterval(61))
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(notices.entries.first?.kind, .activity)
        XCTAssertFalse(notices.entries.first?.systemNotification ?? true)
    }
    func testStableInstallRejectsPreviewAndOtherRepositoryAndHonorsDisabledChecks() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notices = ClientNoticeCenter(preferences: defaults)
        let releases = [release("v1.0.2"), release("v2.0.0-preview", preview: true), release("v9.0.0", repository: "other/app")]
        var requests = 0
        let monitor = UpdateMonitor(notices: notices, preferences: defaults, current: "v1.0.2", previews: false, loader: { requests += 1; return releases })
        monitor.automatic = false
        await monitor.check()
        XCTAssertEqual(requests, 0)
        await monitor.check(manual: true)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(notices.entries.isEmpty)
        XCTAssertTrue(monitor.message.contains("最新公开版本"))
    }
}
