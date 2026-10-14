// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import Darwin
import WakeMacCore

private struct Arguments {
    let operation: String
    var positional: [String] = []
    var options: [String: String] = [:]
    var json = false
    var command: [String] = []
    init(_ arguments: [String]) throws {
        operation = arguments.first ?? "help"
        var index = 1
        let allowed: Set<String> = ["--socket", "--title", "--mode", "--screen", "--lease", "--timeout", "--owner-pid", "--after", "--exit-code"]
        while index < arguments.count {
            let item = arguments[index]
            if item == "--" { command = Array(arguments.dropFirst(index + 1)); break }
            if item == "--json" { json = true; index += 1; continue }
            if item.hasPrefix("--") {
                guard allowed.contains(item), index + 1 < arguments.count, options[item] == nil else { throw ModeError("Unknown, duplicate or incomplete option: " + item) }
                options[item] = arguments[index + 1]; index += 2
            } else { positional.append(item); index += 1 }
        }
        let common: Set<String> = ["--socket"]
        let registration: Set<String> = ["--title", "--mode", "--screen", "--lease", "--timeout", "--owner-pid", "--after"]
        let valid = common.union(["register", "run"].contains(operation) ? registration : ["complete", "fail"].contains(operation) ? ["--exit-code"] : [])
        guard Set(options.keys).isSubset(of: valid), operation == "run" || command.isEmpty else { throw ModeError("Option does not apply to this command") }
    }
    var socket: String { options["--socket"] ?? ProcessInfo.processInfo.environment["OREXIN_SOCKET"] ?? LocalControlSocket.defaultPath }
    func handle() throws -> WorkRequestHandle {
        guard positional.count == 1 else { throw ModeError("Expected ID:TOKEN owner handle") }
        let fields = positional[0].split(separator: ":")
        guard fields.count == 2, let id = UUID(uuidString: String(fields[0])), let token = UUID(uuidString: String(fields[1])) else { throw ModeError("Invalid ID:TOKEN owner handle") }
        return .init(id: id, token: token)
    }
    func spec(wrapping: Bool) throws -> WorkRequestSpec {
        guard positional.isEmpty else { throw ModeError("Unexpected positional argument") }
        guard let mode = WorkMode(rawValue: options["--mode"] ?? "desk"), mode != .normal,
              let screen = RequestScreen(rawValue: options["--screen"] ?? "idle") else { throw ModeError("Use --mode desk|background and --screen idle|dim|awake") }
        let after = options["--after"] ?? "restore"
        guard ["restore", "sleep"].contains(after) else { throw ModeError("Use --after restore|sleep") }
        let lease = try seconds("--lease", fallback: 60)
        guard (5...3600).contains(lease) else { throw ModeError("Lease must be 5–3600 seconds") }
        let deadline = try options["--timeout"].map { _ in Date().addingTimeInterval(try seconds("--timeout", fallback: 60)) }
        var process: LocalProcessIdentity?
        if wrapping {
            guard options["--owner-pid"] == nil else { throw ModeError("run monitors its own wrapper; --owner-pid is only for register") }
            process = LocalProcessIdentity.capture(pid: getpid())
            guard process != nil else { throw ModeError("Could not verify wrapper process identity") }
        } else if let text = options["--owner-pid"] {
            guard let pid = Int32(text), let identity = LocalProcessIdentity.capture(pid: pid) else { throw ModeError("PID must identify a live process owned by the current user") }
            process = identity
        }
        return .init(title: options["--title"] ?? (wrapping ? URL(fileURLWithPath: command.first ?? "command").lastPathComponent : "External task"),
                     mode: mode, screen: screen, deadline: deadline, leaseSeconds: lease, process: process, teardown: after == "sleep" ? .sleepOnSuccess : .restore)
    }
    private func seconds(_ option: String, fallback: Double) throws -> Double {
        guard let text = options[option] else { return fallback }
        guard let value = Double(text), value.isFinite, value > 0, value <= 604800 else { throw ModeError(option + " requires finite seconds in (0, 604800]") }
        return value
    }
}

@main struct OrexinCLI {
    static let help = """
    orexin — independent local keep-awake requests (Orexin app must be running)
      run [options] -- COMMAND [ARG ...]    Wrap a foreground command; preserve exit status
      register [options]                   Print ID:TOKEN owner handle
      heartbeat ID:TOKEN                   Renew the bounded lease
      complete ID:TOKEN --exit-code N      Report an actual command result
      fail ID:TOKEN --exit-code N          Report a nonzero failure
      release ID:TOKEN                     Release this request; do not kill its process
      cancel ID:TOKEN                      Alias for release
      status [ID] | list                   Show actual request and power status
      stop-all                            Global user override; processes continue
    Registration options:
      --title TEXT --mode desk|background --screen idle|dim|awake
      --lease SECONDS (5–3600, default 60) --timeout SECONDS
      --after restore|sleep (default restore; sleep needs successful completion)
      --owner-pid PID (register only, long-lived reporter/shell PID, not the awaited worker; must live through complete)
    All commands accept --json and --socket PATH (or OREXIN_SOCKET).
    run --json redirects child output to stderr and emits one final JSON reply on stdout.
    Owner handles authorize mutations; status/list never disclose their tokens.
    """
    static func main() async {
        var json = CommandLine.arguments.dropFirst().prefix { $0 != "--" }.contains("--json")
        do {
            let args = try Arguments(Array(CommandLine.arguments.dropFirst())); json = args.json
            if ["help", "--help", "-h"].contains(args.operation) { print(help); return }
            if args.operation == "run" { exit(try await run(args)) }
            let request: ControlMessage
            switch args.operation {
            case "register": request = .init("register", handle: .init(), spec: try args.spec(wrapping: false))
            case "heartbeat", "release", "cancel": request = .init(args.operation == "cancel" ? "release" : args.operation, handle: try args.handle())
            case "complete", "fail":
                guard let text = args.options["--exit-code"], let code = Int32(text), args.operation != "fail" || code != 0 else { throw ModeError("Report an actual --exit-code (nonzero for fail)") }
                request = .init("complete", handle: try args.handle(), exitCode: code)
            case "status", "list":
                guard args.positional.count <= (args.operation == "status" ? 1 : 0) else { throw ModeError("status accepts at most one ID; list accepts none") }
                let id = args.positional.first.flatMap(UUID.init(uuidString:))
                guard args.positional.isEmpty || id != nil else { throw ModeError("Invalid request ID") }
                request = .init(args.operation, id: id)
            case "stop-all":
                guard args.positional.isEmpty else { throw ModeError("stop-all does not accept arguments") }
                request = .init("stop-all")
            default: throw ModeError("Unknown command. Run orexin help.")
            }
            let reply = try LocalControlSocket.call(request, path: args.socket)
            try printReply(reply, json: json)
            if !reply.ok { if !json { diagnostic(reply.error ?? "Local control failed") }; exit(1) }
        } catch {
            if json, let data = try? ControlCoding.encode(ControlReply(ok: false, error: error.localizedDescription)) { print(String(decoding: data, as: UTF8.self)) }
            else { diagnostic(error.localizedDescription) }
            exit(1)
        }
    }
    static func call(_ message: ControlMessage, path: String) throws -> ControlReply {
        let reply = try LocalControlSocket.call(message, path: path)
        guard reply.ok else { throw ModeError(reply.error ?? "Local control failed") }
        return reply
    }
    static func printReply(_ reply: ControlReply, json: Bool) throws {
        if json { print(String(decoding: try ControlCoding.encode(reply), as: UTF8.self)); return }
        if let handle = reply.handle { print("\(handle.id.uuidString):\(handle.token.uuidString)"); return }
        print("mode=\(reply.mode?.rawValue ?? "unknown") verified=\(reply.verified) tasks=\(reply.tasks.count)")
        for task in reply.tasks {
            let item = task.request
            print("\(item.id.uuidString)\t\(item.state.rawValue)\t\(item.spec.mode.rawValue)/\(item.spec.screen.rawValue)\t\(task.satisfied ? "verified" : task.detail)\t\(item.spec.title)")
        }
    }
    static func diagnostic(_ text: String) { try? FileHandle.standardError.write(contentsOf: Data(("orexin: " + text + "\n").utf8)) }
    private static func run(_ args: Arguments) async throws -> Int32 {
        guard !args.command.isEmpty else { throw ModeError("run requires -- COMMAND [ARG ...]") }
        let spec = try args.spec(wrapping: true), handle = WorkRequestHandle()
        let registered = try call(.init("register", handle: handle, spec: spec), path: args.socket)
        guard registered.tasks.first?.satisfied == true else { throw ModeError("Request was not verified; command was not started") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = args.command
        process.standardInput = FileHandle.standardInput
        process.standardOutput = args.json ? FileHandle.standardError : FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do { try process.run() }
        catch {
            _ = try? call(.init("complete", handle: handle, exitCode: 127), path: args.socket)
            throw error
        }
        let signals = ForwardSignals(pid: process.processIdentifier)
        defer { signals.stop() }
        var nextHeartbeat = Date().addingTimeInterval((spec.leaseSeconds ?? 60) / 3)
        var coordinationError: String?
        while process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
            if process.isRunning, Date() >= nextHeartbeat, coordinationError == nil {
                do {
                    let reply = try await Task.detached { try call(.init("heartbeat", handle: handle), path: args.socket) }.value
                    if reply.tasks.first?.satisfied != true { throw ModeError("Keep-awake request is no longer satisfied") }
                } catch { coordinationError = error.localizedDescription; diagnostic("Protection ended; command continues: " + error.localizedDescription) }
                nextHeartbeat = Date().addingTimeInterval((spec.leaseSeconds ?? 60) / 3)
            }
        }
        process.waitUntilExit()
        let code = process.terminationReason == .exit ? process.terminationStatus : -process.terminationStatus
        do {
            var reply = try LocalControlSocket.call(.init("complete", handle: handle, exitCode: code), path: args.socket)
            if !reply.ok { coordinationError = coordinationError ?? reply.error ?? "Final cleanup was not verified" }
            if let state = reply.tasks.first?.request.state, ![RequestState.succeeded, .failed, .cancelled].contains(state) {
                coordinationError = coordinationError ?? "Request ended as \(state.rawValue) before command completion"
            }
            if let coordinationError {
                reply.ok = false; reply.error = coordinationError
                if !args.json { diagnostic(coordinationError) }
            }
            if args.json { try printReply(reply, json: true) }
        } catch {
            coordinationError = error.localizedDescription
            if args.json { try printReply(ControlReply(ok: false, error: error.localizedDescription), json: true) }
            else { diagnostic(error.localizedDescription) }
        }
        return code == 0 && coordinationError != nil ? 75 : code < 0 ? 128 - code : code
    }
}

private final class ForwardSignals {
    private var sources: [DispatchSourceSignal] = []
    init(pid: pid_t) {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { _ = kill(pid, number) }
            source.resume(); sources.append(source)
        }
    }
    func stop() { sources.forEach { $0.cancel() }; sources.removeAll() }
}
