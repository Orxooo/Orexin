// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

public enum RequestScreen: String, Codable, Sendable, CaseIterable {
    case idle, dim, awake
    public var priority: Int { self == .awake ? 2 : self == .dim ? 1 : 0 }
}
public enum RequestTeardown: String, Codable, Sendable { case restore, sleepOnSuccess }
public enum RequestState: String, Codable, Sendable {
    case active, succeeded, failed, cancelled, lost, expired, overridden, rejected
}
public struct WorkRequestHandle: Codable, Equatable, Sendable {
    public let id: UUID
    public let token: UUID
    public init(id: UUID = UUID(), token: UUID = UUID()) { self.id = id; self.token = token }
}
public struct WorkRequestSpec: Codable, Equatable, Sendable {
    public var title: String
    public var source: String
    public var mode: WorkMode
    public var screen: RequestScreen
    public var deadline: Date?
    public var leaseSeconds: TimeInterval?
    public var process: LocalProcessIdentity?
    public var teardown: RequestTeardown
    public var profileID: UUID?
    public init(title: String, source: String = "external", mode: WorkMode = .desk, screen: RequestScreen = .idle,
                deadline: Date? = nil, leaseSeconds: TimeInterval? = nil, process: LocalProcessIdentity? = nil,
                teardown: RequestTeardown = .restore, profileID: UUID? = nil) {
        self.title = title; self.source = source; self.mode = mode; self.screen = screen
        self.deadline = deadline; self.leaseSeconds = leaseSeconds; self.process = process; self.teardown = teardown
        self.profileID = profileID
    }
}
public struct WorkRequestRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let spec: WorkRequestSpec
    public let createdAt: Date
    public internal(set) var state: RequestState = .active
    public internal(set) var leaseExpiresAt: Date?
    public internal(set) var endedAt: Date?
    public internal(set) var exitCode: Int32?
    public internal(set) var reason: String?
}
public struct WorkRequestDemand: Equatable, Sendable {
    public let mode: WorkMode
    public let screen: RequestScreen
}

/// Value-type policy only. No power effects and no command execution. Terminal IDs
/// are tombstones: retries and late callbacks cannot acquire a new assertion.
public struct WorkRequestLedger: Sendable {
    public private(set) var records: [WorkRequestRecord] = []
    private var tokens: [UUID: UUID] = [:]
    private var wantsSleep = false
    private var sleepVetoed = false
    public init() {}
    public init(recovering records: [WorkRequestRecord], now: Date) {
        self.records = records.suffix(200).map { record in
            var value = record
            if value.state == .active { value.state = .lost; value.endedAt = now; value.reason = "Application restarted; completion is unknown" }
            return value
        }
    }
    /// Read-only client projection; owner capabilities stay in the service.
    public init(observing records: [WorkRequestRecord]) { self.records = records }
    public var active: [WorkRequestRecord] { records.filter { $0.state == .active } }
    public var demand: WorkRequestDemand? {
        let live = active
        guard !live.isEmpty else { return nil }
        return .init(mode: live.contains { $0.spec.mode == .background } ? .background : .desk,
                     screen: live.map(\.spec.screen).max { $0.priority < $1.priority } ?? .idle)
    }
    @discardableResult public mutating func register(_ spec: WorkRequestSpec, handle: WorkRequestHandle = .init(), now: Date) throws -> WorkRequestHandle {
        if let existing = records.first(where: { $0.id == handle.id }) {
            _ = try authorized(handle)
            guard existing.spec == spec, existing.state == .active else { throw ModeError("Request already ended or registration differs") }
            return handle
        }
        guard !spec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, spec.title.utf8.count <= 256,
              spec.source.utf8.count <= 80, spec.mode != .normal,
              spec.deadline.map({ $0.timeIntervalSince1970.isFinite && $0 > now }) ?? true,
              spec.leaseSeconds.map({ $0.isFinite && (5...3600).contains($0) }) ?? true else {
            throw ModeError("Invalid request: title 1–256 bytes, work mode, future deadline, lease 5–3600 seconds required")
        }
        guard active.count < 64 else { throw ModeError("At most 64 active requests are supported") }
        if active.isEmpty { wantsSleep = false; sleepVetoed = false }
        // Keep all active entries and the latest 200 terminal results.
        let remove = records.filter { $0.state != .active }.dropLast(199).map(\.id)
        records.removeAll { remove.contains($0.id) }; remove.forEach { tokens.removeValue(forKey: $0) }
        tokens[handle.id] = handle.token
        records.append(.init(id: handle.id, spec: spec, createdAt: now, leaseExpiresAt: spec.leaseSeconds.map { now.addingTimeInterval($0) }))
        return handle
    }
    public mutating func heartbeat(_ handle: WorkRequestHandle, now: Date) throws {
        let index = try authorized(handle)
        guard records[index].state == .active, !isExpired(records[index], now: now) else { throw ModeError("Request is no longer active") }
        guard let lease = records[index].spec.leaseSeconds else { throw ModeError("Request does not use a heartbeat lease") }
        records[index].leaseExpiresAt = now.addingTimeInterval(lease)
    }
    @discardableResult public mutating func complete(_ handle: WorkRequestHandle, exitCode: Int32, now: Date) throws -> RequestTeardown? {
        let index = try authorized(handle)
        // Preserve the release reason while recording a real late exit signal.
        guard records[index].state == .active else {
            if records[index].exitCode == nil { records[index].exitCode = exitCode }
            return nil
        }
        records[index].exitCode = exitCode
        if isExpired(records[index], now: now) { return finish(index, state: .expired, reason: "Deadline or heartbeat lease expired", now: now) }
        return finish(index, state: exitCode == 0 ? .succeeded : exitCode < 0 ? .cancelled : .failed, reason: nil, now: now)
    }
    @discardableResult public mutating func release(_ handle: WorkRequestHandle, now: Date) throws -> RequestTeardown? {
        let index = try authorized(handle)
        return try release(id: records[index].id, state: .cancelled, reason: "Owner released keep-awake request; process is unchanged", now: now)
    }
    @discardableResult public mutating func release(id: UUID, state: RequestState = .cancelled, reason: String, now: Date) throws -> RequestTeardown? {
        guard state != .active && state != .succeeded, let index = records.firstIndex(where: { $0.id == id }) else { throw ModeError("Unknown request or invalid release state") }
        guard records[index].state == .active else { return nil }
        return finish(index, state: state, reason: reason, now: now)
    }
    public mutating func cancelSleep() { sleepVetoed = true }
    public mutating func stopAll(reason: String, now: Date) {
        sleepVetoed = true
        for index in records.indices where records[index].state == .active {
            records[index].state = .overridden; records[index].reason = reason; records[index].endedAt = now
        }
    }
    @discardableResult public mutating func reap(now: Date, processAlive: (LocalProcessIdentity) -> Bool?) -> RequestTeardown? {
        var result: RequestTeardown?
        for index in records.indices where records[index].state == .active {
            if isExpired(records[index], now: now) {
                result = finish(index, state: .expired, reason: "Deadline or heartbeat lease expired", now: now) ?? result
            } else if let process = records[index].spec.process, processAlive(process) == false {
                result = finish(index, state: .lost, reason: "Owner process disappeared; completion is unknown", now: now) ?? result
            }
        }
        return result
    }
    private func authorized(_ handle: WorkRequestHandle) throws -> Int {
        guard tokens[handle.id] == handle.token, let index = records.firstIndex(where: { $0.id == handle.id }) else { throw ModeError("Unknown request or invalid owner token") }
        return index
    }
    private func isExpired(_ record: WorkRequestRecord, now: Date) -> Bool {
        [record.spec.deadline, record.leaseExpiresAt].compactMap { $0 }.contains { now >= $0 }
    }
    private mutating func finish(_ index: Int, state: RequestState, reason: String?, now: Date) -> RequestTeardown? {
        records[index].state = state; records[index].reason = reason; records[index].endedAt = now
        if state == .succeeded && records[index].spec.teardown == .sleepOnSuccess { wantsSleep = true }
        if state != .succeeded { sleepVetoed = true }
        return active.isEmpty ? (wantsSleep && !sleepVetoed ? .sleepOnSuccess : .restore) : nil
    }
}
