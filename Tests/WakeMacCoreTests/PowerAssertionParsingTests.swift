// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
@testable import WakeMacCore

final class PowerAssertionParsingTests: XCTestCase {
    private func assertion(_ type: String, level: Int = 255) -> [String: Any] {
        ["AssertType": type, "AssertLevel": level]
    }

    func testOnlyActiveAssertionsAreGroupedAndAttributionUsesPID() {
        let sample = PowerAssertionParser.parse(byProcess: [
            NSNumber(value: 20): [assertion("PreventUserIdleSystemSleep"), assertion("PreventUserIdleSystemSleep"), assertion("PreventUserIdleDisplaySleep", level: 0)],
            NSNumber(value: 30): [assertion("PreventUserIdleDisplaySleep")]
        ], systemStatus: ["PreventUserIdleSystemSleep": 1, "PreventUserIdleDisplaySleep": 1], ownPID: 20, applicationName: { _ in "Orexin" })
        XCTAssertEqual(sample.assertions.count, 2)
        XCTAssertEqual(sample.ownCount, 2)
        XCTAssertEqual(sample.externalCount, 1)
        XCTAssertTrue(sample.assertions[0].isOrexin)
        XCTAssertFalse(sample.assertions[1].isOrexin, "A foreign process named Orexin is still external")
        XCTAssertTrue(sample.unattributedTypes.isEmpty)
        XCTAssertFalse(sample.incomplete)
    }

    func testPrivateDescriptionsAndUnknownRawTypesNeverEnterSnapshot() throws {
        var raw = assertion("private-unknown-type-SECRET")
        raw["AssertName"] = "SECRET /Users/someone/project"
        raw["Details"] = "SECRET --token credentials"
        raw["HumanReadableReason"] = "SECRET https://private.example"
        let sample = PowerAssertionParser.parse(byProcess: [NSNumber(value: 42): [raw]],
            systemStatus: ["private-unknown-type-SECRET": 1], ownPID: 99, applicationName: { _ in " Example\nApp\t " })
        XCTAssertEqual(sample.assertions.first?.kind, .other)
        XCTAssertEqual(sample.assertions.first?.applicationName, "ExampleApp")
        XCTAssertEqual(sample.activeSystemTypes, [.other])
        XCTAssertEqual(sample.unattributedTypes, [.other], "Unsupported types cannot be attributed by their shared fallback label")
        let data = try JSONEncoder().encode(sample)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SECRET"))
        XCTAssertEqual(try JSONDecoder().decode(PowerAssertionSnapshot.self, from: data), sample)
    }

    func testUnavailableAndMalformedDataRemainExplicitlyIncomplete() {
        let missing = PowerAssertionParser.parse(byProcess: nil, systemStatus: nil, ownPID: 1, applicationName: { _ in nil })
        XCTAssertFalse(missing.processesReadable)
        XCTAssertFalse(missing.statusReadable)
        let malformed = PowerAssertionParser.parse(byProcess: ["not a PID": [], NSNumber(value: 12): [["AssertType": "UserIsActive"]]],
            systemStatus: ["PreventUserIdleSystemSleep": 1], ownPID: 1, applicationName: { _ in nil })
        XCTAssertTrue(malformed.incomplete)
        XCTAssertEqual(malformed.unattributedTypes, [.idleSystem])
        XCTAssertTrue(malformed.assertions.isEmpty)
    }

    func testBoundsCountAssertionsAndMarkPartialResult() {
        let raw = Array(repeating: assertion("PreventUserIdleSystemSleep"), count: PowerAssertionParser.maximumAssertions)
        let sample = PowerAssertionParser.parse(byProcess: [NSNumber(value: 10): raw, NSNumber(value: 11): [assertion("UserIsActive")]],
            systemStatus: [:], ownPID: 1, applicationName: { _ in nil })
        XCTAssertEqual(sample.externalCount, PowerAssertionParser.maximumAssertions)
        XCTAssertTrue(sample.incomplete)
    }

    func testSnapshotDedupIgnoresTimeAndDictionaryOrderButDetectsSourceChange() {
        let first: [AnyHashable: Any] = [NSNumber(value: 9): [assertion("UserIsActive")], NSNumber(value: 8): [assertion("PreventUserIdleSystemSleep")]]
        let second: [AnyHashable: Any] = [NSNumber(value: 8): [assertion("PreventUserIdleSystemSleep")], NSNumber(value: 9): [assertion("UserIsActive")]]
        var tracker = PowerAssertionChangeTracker()
        let old = PowerAssertionParser.parse(byProcess: first, systemStatus: [:], ownPID: 8, applicationName: { _ in "App" }, at: .distantPast)
        let current = PowerAssertionParser.parse(byProcess: second, systemStatus: [:], ownPID: 8, applicationName: { _ in "App" }, at: .distantFuture)
        XCTAssertTrue(tracker.accept(old))
        XCTAssertFalse(tracker.accept(current))
        let changed = PowerAssertionParser.parse(byProcess: second, systemStatus: [:], ownPID: 1, applicationName: { _ in "App" })
        XCTAssertTrue(tracker.accept(changed))
        XCTAssertFalse(tracker.accept(changed))
    }

    func testOwnProcessRemainsVisibleWhenObservationIsCapped() {
        var processes: [AnyHashable: Any] = [:]
        for pid in 1...130 { processes[NSNumber(value: pid)] = [assertion("UserIsActive")] }
        let sample = PowerAssertionParser.parse(byProcess: processes, systemStatus: [:], ownPID: 130, applicationName: { _ in nil })
        XCTAssertEqual(sample.ownCount, 1)
        XCTAssertEqual(sample.assertions.count, PowerAssertionParser.maximumProcesses)
        XCTAssertTrue(sample.incomplete)
    }
}
