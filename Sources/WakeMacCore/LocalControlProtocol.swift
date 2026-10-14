// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

public struct ControlMessage: Codable, Sendable {
    public var version = 1
    public var operation: String
    public var handle: WorkRequestHandle?
    public var spec: WorkRequestSpec?
    public var id: UUID?
    public var exitCode: Int32?
    public init(_ operation: String, handle: WorkRequestHandle? = nil, spec: WorkRequestSpec? = nil, id: UUID? = nil, exitCode: Int32? = nil) {
        self.operation = operation; self.handle = handle; self.spec = spec; self.id = id; self.exitCode = exitCode
    }
}
public struct ControlTaskStatus: Codable, Sendable {
    public let request: WorkRequestRecord
    public let satisfied: Bool
    public let detail: String
    public let commandRunning: Bool
    public init(request: WorkRequestRecord, satisfied: Bool, detail: String, commandRunning: Bool) {
        self.request = request; self.satisfied = satisfied; self.detail = detail; self.commandRunning = commandRunning
    }
}
public struct ControlReply: Codable, Sendable {
    public var version = 1
    public var ok: Bool
    public var error: String?
    public var handle: WorkRequestHandle?
    public var tasks: [ControlTaskStatus]
    public var mode: WorkMode?
    public var verified: Bool
    public var sleepAt: Date?
    public init(ok: Bool = true, error: String? = nil, handle: WorkRequestHandle? = nil, tasks: [ControlTaskStatus] = [], mode: WorkMode? = nil, verified: Bool = false, sleepAt: Date? = nil) {
        self.ok = ok; self.error = error; self.handle = handle; self.tasks = tasks; self.mode = mode; self.verified = verified; self.sleepAt = sleepAt
    }
}
public enum ControlCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
