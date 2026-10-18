// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
import WakeMacCore
@testable import WakeMac

@MainActor final class PowerAnalysisTests: XCTestCase {
    func testLegacyHistoryDecodesAndNewContextRoundTrips() throws {
        let data = Data("[{\"id\":\"2D41520B-8A72-4CFB-A0B1-A64494DBFBE5\",\"date\":0,\"text\":\"legacy\"}]".utf8)
        let legacy = try JSONDecoder().decode([HistoryEntry].self, from: data)
        XCTAssertNil(legacy.first?.context)
        let request = UUID(), rule = UUID(), date = Date(timeIntervalSince1970: 100)
        let store = HistoryStore(url: nil)
        let context = HistoryContext(kind: .powerAssertion, requestIDs: [request], ruleID: rule, mode: "桌面工作")
        store.append("电源断言变化", context: context, at: date)
        let restored = try JSONDecoder().decode([HistoryEntry].self, from: JSONEncoder().encode(store.entries))
        XCTAssertEqual(restored.first?.context, context)
        XCTAssertEqual(restored.first?.date, date)
        XCTAssertTrue(context.searchable.contains(request.uuidString))
        XCTAssertTrue(context.searchable.contains(rule.uuidString))
    }

    func testObserverThrottlesAndDoesNotRecordUnchangedManualRefresh() async {
        let reader = CountingReader()
        let observer = PowerAnalysisObserver(read: { reader.read() })
        var events: [String] = []
        observer.onChange = { events.append($0) }
        let now = Date()
        await observer.refresh(now: now)
        await observer.refresh(now: now.addingTimeInterval(1))
        XCTAssertEqual(reader.count, 1)
        await observer.refresh(force: true, now: now.addingTimeInterval(2))
        XCTAssertEqual(reader.count, 2)
        XCTAssertEqual(events.count, 1)
        await observer.refresh(now: now.addingTimeInterval(33))
        XCTAssertEqual(reader.count, 3)
        XCTAssertEqual(events.count, 1)
        XCTAssertNotNil(observer.snapshot)
        XCTAssertFalse(observer.refreshing)
    }

    func testUnknownSourcesAreNotReportedAsZeroOrAsWakeCause() {
        let missing = PowerAssertionParser.parse(byProcess: nil, systemStatus: ["PreventUserIdleSystemSleep": 1], ownPID: 1, applicationName: { _ in nil })
        let text = PowerAnalysisObserver.historyText(missing)
        XCTAssertTrue(text.contains("未知"))
        XCTAssertFalse(text.contains("Orexin 0"))
        XCTAssertFalse(text.contains("导致"))
    }

    func testTimelineKindsDistinguishRelevantEvents() {
        let examples: [(String, HistoryEventKind)] = [
            ("工作请求已登记", .request), ("自动触发：夜间规则", .rule), ("模式已核验：桌面工作", .mode),
            ("系统即将休眠。", .sleepWake), ("系统已唤醒。", .sleepWake), ("系统显示器已唤醒。", .display),
            ("检测到合盖。", .lid), ("电源已切换：电池", .powerSource), ("电源断言变化", .powerAssertion),
            ("温度保护触发", .protection), ("低电量保护开始恢复正常模式并请求休眠。", .protection)
        ]
        for (text, kind) in examples { XCTAssertEqual(HistoryEventKind.inferred(from: text), kind, text) }
    }
}

private final class CountingReader: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func read() -> PowerAssertionSnapshot {
        lock.lock(); reads += 1; lock.unlock()
        return PowerAssertionParser.parse(byProcess: [:], systemStatus: [:], ownPID: 1, applicationName: { _ in nil })
    }
}
