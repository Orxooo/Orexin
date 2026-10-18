// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import Darwin

public struct TaskServiceInfo: Codable, Sendable {
    public let protocolVersion: Int
    public let instanceID: UUID
    public let pid: Int32
    public let startedAt: Date
    public let stateDirectory: String
    public init(instanceID: UUID = UUID(), pid: Int32 = getpid(), startedAt: Date = Date(), stateDirectory: String) {
        protocolVersion = 1; self.instanceID = instanceID; self.pid = pid; self.startedAt = startedAt; self.stateDirectory = stateDirectory
    }
}
public struct PlanRunSummary: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let state: PlanRunState
    public let total: Int
    public let finished: Int
    public let running: Int
    public let createdAt: Date
    public init(_ run: PlanRun) {
        id = run.id; title = run.plan.title; state = run.state; total = run.tasks.count
        finished = run.tasks.filter { $0.state.terminal }.count; running = run.tasks.filter { $0.state == .running }.count
        createdAt = run.createdAt
    }
}
public enum TaskServiceLauncher {
    public static var socketPath: String { ProcessInfo.processInfo.environment["OREXIN_SOCKET"] ?? LocalControlSocket.defaultPath }
    public static var defaultStateDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Orexin", isDirectory: true) }
    public static var isolatedPreferences: UserDefaults? {
        guard stateDirectory.standardizedFileURL != defaultStateDirectory.standardizedFileURL else { return nil }
        // Include the complete path, encoded without slashes, to isolate same-named directories.
        let name = Data(stateDirectory.path.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return UserDefaults(suiteName: "Orexin.TaskService." + name)
    }
    public static var stateDirectory: URL {
        if let value = ProcessInfo.processInfo.environment["OREXIN_STATE_DIR"] { return URL(fileURLWithPath: value, isDirectory: true) }
        return defaultStateDirectory
    }
    public static func executable(near executable: URL) throws -> URL {
        let directory = executable.deletingLastPathComponent()
        let candidates = [directory.appendingPathComponent("../MacOS/Orexin").standardizedFileURL,
                          directory.appendingPathComponent("Orexin.app/Contents/MacOS/Orexin"), directory.appendingPathComponent("WakeMac"), directory.appendingPathComponent("Orexin")]
        // On case-insensitive volumes, Helpers/Orexin also resolves to the CLI.
        // Prefer the packaged app executable and never launch the CLI as a daemon.
        let callerIdentity = try? executable.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        guard let result = candidates.first(where: { candidate in
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { return false }
            let identity = try? candidate.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            return callerIdentity == nil || identity == nil || !(callerIdentity! as AnyObject).isEqual(identity!)
        }) else {
            throw ModeError("Task service executable not found. Use --service-executable /path/to/Orexin.app/Contents/MacOS/Orexin")
        }
        return result
    }
    /// Does not install a LaunchAgent, mutate login items, or replace another server.
    public static func start(executable: URL, socket: String = socketPath, stateDirectory: URL = stateDirectory) throws -> ControlReply {
        let deadline = Date().addingTimeInterval(10)
        if let current = try? LocalControlSocket.call(.init("service-status"), path: socket) {
            guard current.service?.protocolVersion == 1 else { throw ModeError("This endpoint belongs to an older Orexin app. Quit that app before starting the task service.") }
            if current.ok { return current }
            return try waitForReady(socket: socket, deadline: deadline)
        }
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--task-service"]
        var environment = ProcessInfo.processInfo.environment
        environment["OREXIN_SOCKET"] = socket; environment["OREXIN_STATE_DIR"] = stateDirectory.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        // A competing starter may own the winning child. Its readiness, not the
        // lifetime of our own child, determines whether startup succeeded.
        return try waitForReady(socket: socket, deadline: deadline)
    }
    private static func waitForReady(socket: String, deadline: Date) throws -> ControlReply {
        while Date() < deadline {
            if let reply = try? LocalControlSocket.call(.init("service-status"), path: socket) {
                guard reply.service?.protocolVersion == 1 else { throw ModeError("Local endpoint is not a compatible Orexin task service") }
                if reply.ok { return reply }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw ModeError("Task service did not become ready; inspect task-service.log")
    }
}
