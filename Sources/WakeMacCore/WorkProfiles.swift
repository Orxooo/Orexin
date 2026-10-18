// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

public struct WorkOutcome: Codable, Equatable, Sendable {
    public var teardown: RequestTeardown = .restore
    public var notify = false
    /// A local zsh script, never inline shell text. Activation is local-only.
    public var scriptPath: String?
    public init(teardown: RequestTeardown = .restore, notify: Bool = false, scriptPath: String? = nil) {
        self.teardown = teardown; self.notify = notify; self.scriptPath = scriptPath
    }
}

public struct WorkProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var mode: WorkMode = .desk
    public var screen: RequestScreen = .idle
    public var timeoutSeconds: TimeInterval?
    public var success = WorkOutcome()
    public var failure = WorkOutcome()
    public var timeout = WorkOutcome()
    public init(name: String) { self.name = name }
    public var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 256 else { return "Profile name must contain 1–256 bytes" }
        guard mode != .normal else { return "A work profile requires desk or background mode" }
        if let seconds = timeoutSeconds, !seconds.isFinite || !(1...604800).contains(seconds) { return "Profile timeout must be 1–604800 seconds" }
        guard failure.teardown == .restore, timeout.teardown == .restore else { return "Failure and timeout release wakefulness without requesting sleep" }
        for outcome in [success, failure, timeout] {
            if let path = outcome.scriptPath, !path.hasPrefix("/") || path == "/" || path.utf8.count > 4096 || path.contains("\0") || path.contains("\n") {
                return "Hook script must be an absolute local path"
            }
        }
        return nil
    }
    public func applying(to request: WorkRequestSpec, now: Date) throws -> WorkRequestSpec {
        if let error = validationError { throw ModeError(error) }
        var value = request
        value.mode = mode; value.screen = screen; value.teardown = success.teardown; value.profileID = id
        if let timeoutSeconds {
            value.deadline = min(value.deadline ?? .distantFuture, now.addingTimeInterval(timeoutSeconds))
        }
        return value
    }
    public func outcome(for state: RequestState) -> WorkOutcome? {
        switch state { case .succeeded: success; case .failed: failure; case .expired: timeout; default: nil }
    }
    public var scriptPaths: [String] { Array(Set([success, failure, timeout].compactMap(\.scriptPath))).sorted() }
}
