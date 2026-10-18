// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

public enum PlanDependencyCondition: String, Codable, Sendable { case success, completion, failure }
public struct PlanTask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var command: String
    public var directory: String
    public var dependencies: [String]
    public var condition: PlanDependencyCondition
    public init(id: String, command: String, directory: String, dependencies: [String] = [], condition: PlanDependencyCondition = .success) {
        self.id = id; self.command = command; self.directory = directory; self.dependencies = dependencies; self.condition = condition
    }
    private enum CodingKeys: String, CodingKey { case id, command, directory, dependencies, condition }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); command = try c.decode(String.self, forKey: .command)
        directory = try c.decode(String.self, forKey: .directory)
        dependencies = try c.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        condition = try c.decodeIfPresent(PlanDependencyCondition.self, forKey: .condition) ?? .success
    }
}
public struct ExecutionPlan: Codable, Equatable, Sendable {
    public var version = 1
    public var title: String
    public var tasks: [PlanTask]
    public var maxConcurrent: Int
    public var mode: WorkMode
    public var screen: RequestScreen
    public var teardown: RequestTeardown
    public init(title: String, tasks: [PlanTask], maxConcurrent: Int = 1, mode: WorkMode = .desk, screen: RequestScreen = .idle, teardown: RequestTeardown = .restore) {
        self.title = title; self.tasks = tasks; self.maxConcurrent = maxConcurrent; self.mode = mode; self.screen = screen; self.teardown = teardown
    }
    private enum CodingKeys: String, CodingKey { case version, title, tasks, maxConcurrent, mode, screen, teardown }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version); title = try c.decode(String.self, forKey: .title)
        tasks = try c.decode([PlanTask].self, forKey: .tasks)
        maxConcurrent = try c.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 1
        mode = try c.decodeIfPresent(WorkMode.self, forKey: .mode) ?? .desk
        screen = try c.decodeIfPresent(RequestScreen.self, forKey: .screen) ?? .idle
        teardown = try c.decodeIfPresent(RequestTeardown.self, forKey: .teardown) ?? .restore
    }
    @discardableResult public func validated() throws -> Self {
        guard version == 1, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 256,
              (1...64).contains(tasks.count), (1...16).contains(maxConcurrent), mode != .normal else {
            throw ModeError("Plan requires version 1, title (1–256 bytes), 1–64 tasks, concurrency 1–16 and a work mode")
        }
        let ids = Set(tasks.map(\.id))
        guard ids.count == tasks.count else { throw ModeError("Duplicate plan task ID") }
        for task in tasks {
            guard !task.id.isEmpty, task.id.utf8.count <= 80,
                  task.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }),
                  !task.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.command.utf8.count <= 16 * 1024,
                  !task.command.contains("\0"), task.directory.hasPrefix("/"), !task.directory.contains("\0"), task.directory.utf8.count <= 4096,
                  Set(task.dependencies).count == task.dependencies.count, Set(task.dependencies).isSubset(of: ids),
                  !task.dependencies.contains(task.id), task.condition != .failure || !task.dependencies.isEmpty else {
                throw ModeError("Invalid task, directory or dependencies: " + task.id)
            }
        }
        var resolved = Set<String>()
        while resolved.count < tasks.count {
            let ready = tasks.filter { !resolved.contains($0.id) && Set($0.dependencies).isSubset(of: resolved) }
            guard !ready.isEmpty else { throw ModeError("Plan dependencies contain a cycle") }
            resolved.formUnion(ready.map(\.id))
        }
        guard try ControlCoding.encode(self).count <= 32 * 1024 else { throw ModeError("Execution plan exceeds 32 KiB") }
        return self
    }
}

public enum PlanTaskState: String, Codable, Sendable {
    case pending, running, succeeded, failed, skipped, lost
    public var terminal: Bool { self != .pending && self != .running }
}
public enum PlanRunState: String, Codable, Sendable {
    case running, cancelling, succeeded, failed, cancelled, lost
    public var terminal: Bool { self != .running && self != .cancelling }
}
public struct PlanTaskResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public internal(set) var state: PlanTaskState = .pending
    public internal(set) var startedAt: Date?
    public internal(set) var endedAt: Date?
    public internal(set) var exitCode: Int32?
    public internal(set) var detail: String?
}
public struct PlanRun: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let plan: ExecutionPlan
    public let createdAt: Date
    public private(set) var state: PlanRunState = .running
    public private(set) var tasks: [PlanTaskResult]
    public private(set) var endedAt: Date?
    public init(id: UUID = UUID(), plan: ExecutionPlan, now: Date = Date()) throws {
        self.id = id; self.plan = try plan.validated(); createdAt = now
        tasks = plan.tasks.map { PlanTaskResult(id: $0.id) }
    }
    /// Reserve before launching so reentrant ticks cannot launch a task twice.
    public mutating func schedule(now: Date) -> [String] {
        guard state == .running else { return [] }
        var changed = true
        while changed {
            changed = false
            for i in tasks.indices where tasks[i].state == .pending {
                let spec = plan.tasks[i], deps = tasks.filter { spec.dependencies.contains($0.id) }
                guard deps.allSatisfy({ $0.state.terminal }) else { continue }
                let meets = spec.condition == .completion || (spec.condition == .success && deps.allSatisfy { $0.state == .succeeded }) || (spec.condition == .failure && deps.contains { $0.state == .failed || $0.state == .lost })
                if !meets { tasks[i].state = .skipped; tasks[i].endedAt = now; tasks[i].detail = "Dependency condition not met"; changed = true }
            }
        }
        var capacity = plan.maxConcurrent - tasks.filter { $0.state == .running }.count
        var ready: [String] = []
        for i in tasks.indices where tasks[i].state == .pending && capacity > 0 {
            let deps = tasks.filter { plan.tasks[i].dependencies.contains($0.id) }
            guard deps.allSatisfy({ $0.state.terminal }) else { continue }
            tasks[i].state = .running; tasks[i].startedAt = now; ready.append(tasks[i].id); capacity -= 1
        }
        settle(now: now)
        return ready
    }
    public mutating func finish(_ id: String, exitCode: Int32, detail: String? = nil, now: Date) {
        guard !state.terminal, let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].state == .running else { return }
        tasks[i].state = exitCode == 0 ? .succeeded : .failed
        tasks[i].exitCode = exitCode; tasks[i].endedAt = now; tasks[i].detail = detail
        settle(now: now)
    }
    public mutating func cancel(now: Date) {
        guard !state.terminal else { return }
        state = .cancelling
        for i in tasks.indices where tasks[i].state == .pending {
            tasks[i].state = .skipped; tasks[i].endedAt = now; tasks[i].detail = "Plan cancelled before launch"
        }
        settle(now: now)
    }
    public mutating func recover(now: Date) {
        guard !state.terminal else { return }
        state = .lost; endedAt = now
        for i in tasks.indices where !tasks[i].state.terminal {
            tasks[i].state = .lost; tasks[i].endedAt = now; tasks[i].detail = "Service restarted; not replayed; command result unknown"
        }
    }
    private mutating func settle(now: Date) {
        guard !state.terminal, tasks.allSatisfy({ $0.state.terminal }) else { return }
        state = state == .cancelling ? .cancelled : tasks.contains(where: { $0.state == .failed || $0.state == .lost }) ? .failed : .succeeded
        endedAt = now
    }
}
