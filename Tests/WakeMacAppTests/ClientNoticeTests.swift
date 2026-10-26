import XCTest
import UserNotifications
import WakeMacCore
@testable import WakeMac

@MainActor final class ClientNoticeTests: XCTestCase {
    private func preferences() -> UserDefaults { UserDefaults(suiteName: "NoticeTests." + UUID().uuidString)! }
    func testInboxAndReadStateSurviveRestartAndEventIsNotRepeated() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/notices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let center = ClientNoticeCenter(url: url, preferences: preferences())
        center.post(.serviceFailure, title: "服务中断", body: "保活无法确认", id: "incident")
        center.acknowledge("incident")
        let reopened = ClientNoticeCenter(url: url, preferences: preferences())
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.unreadCount, 0)
        XCTAssertFalse(reopened.post(.serviceFailure, title: "重复", body: "重复", id: "incident"))
    }
    func testImportedServiceEventDoesNotRedeliverExternallyOrReplayAfterPruning() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/notices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let center = ClientNoticeCenter(url: url, preferences: preferences())
        let remote = ClientNotice(id: "remote", date: Date(timeIntervalSince1970: 1), kind: .thermal,
                                  title: "温度保护", body: "已触发", releaseURL: nil)
        var deliveries: [Bool] = []
        center.onArrival = { _, external in deliveries.append(external) }
        center.ingest([remote])
        XCTAssertEqual(deliveries, [false])
        for i in 0..<101 { center.post(.activity, title: "event", body: "message", id: "local.\(i)") }
        let count = deliveries.count
        center.ingest([remote]); XCTAssertEqual(deliveries.count, count)
        let reopened = ClientNoticeCenter(url: url, preferences: preferences())
        reopened.onArrival = { _, external in deliveries.append(external) }
        reopened.ingest([remote])
        XCTAssertEqual(deliveries.count, count)
        XCTAssertEqual(reopened.entries.count, 100)
    }
    func testDeniedSystemNotificationKeepsInAppMessageAndExplainsFallback() async {
        let center = ClientNoticeCenter(preferences: preferences())
        center.post(.test, title: "通知测试", body: "test")
        let notifier = LocalNotifier(readAuthorization: { .denied }, preferences: preferences())
        let sent = await notifier.sendNotice(center.entries[0])
        XCTAssertFalse(sent)
        XCTAssertEqual(center.unreadCount, 1)
        XCTAssertTrue(notifier.message.contains("应用内"))
    }
    func testDeadlineWarningIsOncePerDeadlineAndRearmsAfterExtension() {
        let model = AppModel(backend: AutomationBackend(), preferences: preferences())
        let now = Date()
        model.automation.deadline = now.addingTimeInterval(301)
        model.checkSessionEndingNotice(now: now)
        XCTAssertTrue(model.notices.entries.isEmpty)
        model.checkSessionEndingNotice(now: now.addingTimeInterval(2))
        model.checkSessionEndingNotice(now: now.addingTimeInterval(3))
        XCTAssertEqual(model.notices.entries.filter { $0.kind == .sessionEnding }.count, 1)
        model.automation.deadline = now.addingTimeInterval(600)
        model.checkSessionEndingNotice(now: now.addingTimeInterval(301))
        XCTAssertEqual(model.notices.entries.filter { $0.kind == .sessionEnding }.count, 2)
    }
    func testThermalCoolingReportsRecoveryOnceWithoutRestartingWork() async {
        let model = AppModel(backend: AutomationBackend(), preferences: preferences())
        var thermal: ProcessInfo.ThermalState = .critical
        model.thermalStateProvider = { thermal }
        await model.protectFromThermalPressure()
        await model.protectFromThermalPressure()
        XCTAssertEqual(model.notices.entries.filter { $0.kind == .thermal }.count, 1)
        thermal = .nominal
        await model.protectFromThermalPressure()
        await model.protectFromThermalPressure()
        XCTAssertEqual(model.notices.entries.filter { $0.kind == .thermalRecovery }.count, 1)
        XCTAssertFalse(model.verifiedWork)
    }
    func testExpiredRequestCreatesOneDurableNoticeAndReleasesOnlyItsWork() async throws {
        let model = AppModel(backend: AutomationBackend(), preferences: preferences())
        model.thermalStateProvider = { .nominal }
        await model.choose(.normal)
        let now = Date()
        _ = try await model.registerWork(.init(title: "leased", leaseSeconds: 5), now: now)
        await model.reapWorkRequests(now: now.addingTimeInterval(6))
        await model.reapWorkRequests(now: now.addingTimeInterval(7))
        XCTAssertEqual(model.notices.entries.filter { $0.kind == .leaseExpired }.count, 1)
        XCTAssertEqual(model.active, .normal)
        XCTAssertTrue(model.notices.entries.first?.body.contains("leased") == true)
    }
    func testServiceMessagesRoundTripThroughControlReplyWithoutExtraDelivery() throws {
        let server = AppModel(backend: AutomationBackend(), preferences: preferences())
        server.notices.post(.leaseExpired, title: "请求到期", body: "请检查", id: "lease")
        let data = try ControlCoding.encode(server.taskControlReply())
        let reply = try ControlCoding.decode(ControlReply.self, from: data)
        let client = AppModel(backend: AutomationBackend(), preferences: preferences())
        var external: [Bool] = []
        client.notices.onArrival = { _, value in external.append(value) }
        client.adoptServiceReply(reply); client.adoptServiceReply(reply)
        XCTAssertEqual(client.notices.entries.map(\.id), ["lease"])
        XCTAssertEqual(external, [false])
    }
    func testLongNoticeHistoryCannotOverflowLocalControlTransport() throws {
        let server = AppModel(backend: AutomationBackend(), preferences: preferences())
        for i in 0..<100 {
            server.notices.post(.activity, title: "错误详情", body: String(repeating: "中", count: 4000), id: "\(i)")
        }
        let data = try ControlCoding.encode(server.taskControlReply())
        XCTAssertLessThan(data.count, 128 * 1024)
        let reply = try ControlCoding.decode(ControlReply.self, from: data)
        let notices = try ControlCoding.decode([ClientNotice].self, from: XCTUnwrap(reply.notices))
        XCTAssertFalse(notices.isEmpty)
        XCTAssertEqual(notices.first?.id, "99")
    }
    func testResolvedBackgroundIncidentsRemainInInboxWithoutStalePopupOnReopen() {
        let center = ClientNoticeCenter(preferences: preferences())
        let trigger = ClientNotice(id: "hot", date: Date(timeIntervalSince1970: 1), kind: .thermal,
                                   title: "温度保护", body: "触发", releaseURL: nil)
        let recovery = ClientNotice(id: "cooled", date: Date(timeIntervalSince1970: 2), kind: .thermalRecovery,
                                    title: "已回落", body: "恢复", releaseURL: nil)
        var popups: [String] = []
        center.onArrival = { notice, _ in if notice.kind.requiresPopup { popups.append(notice.id) } }
        center.ingest([recovery, trigger])
        XCTAssertEqual(center.entries.count, 2)
        XCTAssertTrue(popups.isEmpty)
    }
    func testOldServiceWithoutReminderCapabilityIsExplicitlyReportedOnce() {
        let client = AppModel(backend: AutomationBackend(), preferences: preferences())
        var old = ControlReply()
        old.service = TaskServiceInfo(stateDirectory: "/tmp/notices-test")
        client.adoptServiceReply(old); client.adoptServiceReply(old)
        XCTAssertEqual(client.notices.entries.filter { $0.title == "后台提醒尚未完整启用" }.count, 1)
    }
    func testThermalAlarmHonorsItsOwnToggleEvenWhenSystemNotificationsAreDenied() async {
        for enabled in [true, false] {
            let defaults = preferences()
            defaults.set(enabled, forKey: "orexin.thermal.audibleAlert")
            var plays = 0
            let notifier = LocalNotifier(readAuthorization: { .denied }, preferences: defaults, thermalAlarmPlayer: { plays += 1 })
            let note = ClientNotice(kind: .thermal, title: "温度保护", body: "保护已触发", releaseURL: nil)
            _ = await notifier.sendNotice(note)
            XCTAssertEqual(plays, enabled ? 1 : 0)
        }
    }
}
