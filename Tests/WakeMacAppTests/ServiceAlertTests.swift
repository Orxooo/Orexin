import XCTest
import WakeMacCore
@testable import WakeMac

private actor AlertReadbackBackend: ModeBackend {
    var unavailable = true
    func setUnavailable(_ value: Bool) { unavailable = value }
    func snapshot() async throws -> Snapshot {
        if unavailable { throw ModeError("合盖服务响应超时") }
        return Snapshot(sleepDisabled: false, lockPolicy: .immediate, idleSleepPrevented: false,
                        displaySleepAllowed: true, backgroundLeaseActive: false)
    }
    func configurePower(_ mode: WorkMode) async throws {}
    func requestLockPolicy(_ policy: LockPolicy) async {}
    func sleepNow() async throws {}
}

@MainActor final class ServiceAlertTests: XCTestCase {
    func testReadbackFailureNotifiesOnceAndRearmsAfterRecovery() async {
        let backend = AlertReadbackBackend()
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: UUID().uuidString)!)
        var notifications: [String] = []
        model.notificationHandler = { notifications.append($0) }
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(notifications.count, 1)
        await backend.setUnavailable(false)
        await model.refresh()
        await backend.setUnavailable(true)
        await model.refresh()
        XCTAssertEqual(notifications.filter { $0.contains("响应超时") }.count, 2)
    }
}
