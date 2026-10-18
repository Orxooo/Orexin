// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation

/// Only OS assertion types are retained. Assertion names/details can contain private paths or URLs.
public enum PowerAssertionKind: String, Codable, CaseIterable, Sendable {
    case idleSystem = "PreventUserIdleSystemSleep"
    case idleDisplay = "PreventUserIdleDisplaySleep"
    case system = "PreventSystemSleep"
    case disk = "PreventDiskIdle"
    case network = "NetworkClientActive"
    case userActivity = "UserIsActive"
    case background = "BackgroundTask"
    case media = "ExternalMedia"
    case display = "InternalPreventDisplaySleep"
    case other = "Other"

    public var preventsIdleSleep: Bool { self == .idleSystem || self == .system }
    public var keepsDisplayAwake: Bool { self == .idleDisplay || self == .display }
}

public struct PowerAssertionRecord: Codable, Equatable, Identifiable, Sendable {
    public let processID: Int32
    public let applicationName: String?
    public let kind: PowerAssertionKind
    public let count: Int
    public let isOrexin: Bool
    public var id: String { "\(processID):\(kind.rawValue)" }
}

public struct PowerAssertionSnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let assertions: [PowerAssertionRecord]
    public let activeSystemTypes: [PowerAssertionKind]
    public let processesReadable: Bool
    public let statusReadable: Bool
    public let incomplete: Bool

    public var unattributedTypes: [PowerAssertionKind] {
        let attributed = Set(assertions.map(\.kind))
        // Distinct unsupported OS types collapse to .other; they cannot be joined by that label.
        return activeSystemTypes.filter { $0 == .other || !attributed.contains($0) }
    }
    public var ownCount: Int { assertions.filter(\.isOrexin).reduce(0) { $0 + $1.count } }
    public var externalCount: Int { assertions.filter { !$0.isOrexin }.reduce(0) { $0 + $1.count } }
    public func hasSameObservation(as other: Self) -> Bool {
        assertions == other.assertions && activeSystemTypes == other.activeSystemTypes
            && processesReadable == other.processesReadable && statusReadable == other.statusReadable
            && incomplete == other.incomplete
    }
}

public enum PowerAssertionParser {
    public static let maximumProcesses = 128
    public static let maximumAssertions = 512

    /// Accepts the dictionaries returned by IOPMCopyAssertionsByProcess/Status.
    /// Never inspect AssertName, Details, HumanReadableReason, paths, argv, or environment.
    public static func parse(byProcess: [AnyHashable: Any]?, systemStatus: [String: Any]?, ownPID: Int32,
                             applicationName: (Int32) -> String?, at date: Date = Date()) -> PowerAssertionSnapshot {
        var incomplete = false
        var records: [PowerAssertionRecord] = []
        var remaining = maximumAssertions
        let processes = (byProcess ?? [:]).compactMap { key, value -> (Int32, Any)? in
            guard let number = key as? NSNumber, number.int64Value > 0, number.int64Value <= Int32.max,
                  number.doubleValue == Double(number.int64Value) else { incomplete = true; return nil }
            return (number.int32Value, value)
        }.sorted { lhs, rhs in
            if (lhs.0 == ownPID) != (rhs.0 == ownPID) { return lhs.0 == ownPID }
            return lhs.0 < rhs.0
        }
        if processes.count > maximumProcesses { incomplete = true }
        for (index, process) in processes.prefix(maximumProcesses).enumerated() {
            let (pid, value) = process
            guard let raw = value as? [[String: Any]] else { incomplete = true; continue }
            if raw.count > remaining { incomplete = true }
            var counts: [PowerAssertionKind: Int] = [:]
            for assertion in raw.prefix(remaining) {
                guard let level = assertion["AssertLevel"] as? NSNumber,
                      let type = assertion["AssertType"] as? String else { incomplete = true; continue }
                guard level.intValue > 0 else { continue }
                let kind = PowerAssertionKind(rawValue: type) ?? .other
                counts[kind, default: 0] += 1
            }
            remaining = max(0, remaining - raw.count)
            let isOrexin = pid == ownPID
            let name = isOrexin ? "Orexin" : safeApplicationName(applicationName(pid))
            for kind in counts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                records.append(.init(processID: pid, applicationName: name, kind: kind, count: counts[kind]!, isOrexin: isOrexin))
            }
            if remaining == 0 {
                if index + 1 < processes.count { incomplete = true }
                break
            }
        }
        var active: Set<PowerAssertionKind> = []
        for (type, value) in systemStatus ?? [:] {
            guard let level = value as? NSNumber else { incomplete = true; continue }
            if level.intValue > 0 { active.insert(PowerAssertionKind(rawValue: type) ?? .other) }
        }
        return .init(sampledAt: date, assertions: records, activeSystemTypes: active.sorted { $0.rawValue < $1.rawValue },
                     processesReadable: byProcess != nil, statusReadable: systemStatus != nil, incomplete: incomplete)
    }

    private static func safeApplicationName(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(80))
    }
}

/// Snapshot timestamps do not create history events; only a changed observation does.
public struct PowerAssertionChangeTracker: Sendable {
    private var previous: PowerAssertionSnapshot?
    public init() {}
    public mutating func accept(_ snapshot: PowerAssertionSnapshot) -> Bool {
        defer { previous = snapshot }
        return previous.map { !snapshot.hasSameObservation(as: $0) } ?? true
    }
}
