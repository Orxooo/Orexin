// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
@testable import WakeMac

@MainActor final class HistoryStoreTests: XCTestCase {
    func testClearPersistsEmptyHistoryAndPreservesOtherFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMacHistoryTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let store = HistoryStore(url: historyURL)
        store.append("模式已核验：桌面工作")
        store.append("检测到屏幕亮起。")
        let unrelatedURL = directory.appendingPathComponent("unrelated.json")
        let unrelatedData = Data("preserve sibling file".utf8)
        try unrelatedData.write(to: unrelatedURL)

        try store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try String(contentsOf: historyURL, encoding: .utf8), "[]")
        XCTAssertTrue(HistoryStore(url: historyURL).entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedData)
        store.append("应用启动")
        XCTAssertEqual(HistoryStore(url: historyURL).entries.map(\.text), ["应用启动"])
    }

    func testFailedAtomicClearPreservesInMemoryEntriesAndDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMacHistoryTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A directory at the JSON destination makes the atomic file write fail.
        let historyURL = directory.appendingPathComponent("history.json", isDirectory: true)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        let sentinelURL = historyURL.appendingPathComponent("keep.json")
        let sentinelData = Data("do not remove destination contents".utf8)
        try sentinelData.write(to: sentinelURL)
        let store = HistoryStore(url: historyURL)
        store.entries = [HistoryEntry(text: "待保留记录")]
        let originalIDs = store.entries.map(\.id)
        let originalDates = store.entries.map(\.date)
        let originalTexts = store.entries.map(\.text)

        XCTAssertThrowsError(try store.clear())

        XCTAssertEqual(store.entries.map(\.id), originalIDs)
        XCTAssertEqual(store.entries.map(\.date), originalDates)
        XCTAssertEqual(store.entries.map(\.text), originalTexts)
        XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinelData)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
