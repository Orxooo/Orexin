// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import Darwin
import WakeMacCore

/// Owns only explicitly activated outcome scripts, never task/CLI processes.
@MainActor final class WorkPolicyHooks {
    private var running: [UUID: pid_t] = [:]
    var count: Int { running.count }
    func cancelAll() {
        for pid in running.values { kill(-pid, SIGKILL) }
    }
    func run(script: Data, sourcePath: String, record: WorkRequestRecord, limit: TimeInterval = 30) async throws -> Int32 {
        guard running.count < 4 else { throw ModeError("At most four outcome hooks can run concurrently") }
        // Execute the bytes whose approval was checked, never reopen the mutable source path.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orexin-hook-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("approved.zsh").path
        guard FileManager.default.createFile(atPath: path, contents: script, attributes: [.posixPermissions: 0o600]) else { throw ModeError("Cannot prepare approved hook") }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", descriptor == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let arguments: [String] = ["/bin/zsh", "-f", path]
        let argv = arguments.map { value in value.withCString { strdup($0) } } + [nil]
        let environment: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "OREXIN_SCRIPT_PATH=\(sourcePath)", "OREXIN_TASK_ID=\(record.id.uuidString)",
                   "OREXIN_OUTCOME=\(record.state.rawValue)", "OREXIN_EXIT_CODE=\(record.exitCode.map(String.init) ?? "")"]
        let env = environment.map { value in value.withCString { strdup($0) } } + [nil]
        defer { argv.forEach { free($0) }; env.forEach { free($0) } }
        var pid: pid_t = 0
        let error = argv.withUnsafeBufferPointer { a in env.withUnsafeBufferPointer { e in
            posix_spawn(&pid, "/bin/zsh", &actions, &attributes, UnsafeMutablePointer(mutating: a.baseAddress!), UnsafeMutablePointer(mutating: e.baseAddress!))
        } }
        guard error == 0 else { throw ModeError("Could not launch hook (\(error))") }
        let key = UUID(); running[key] = pid
        defer { running.removeValue(forKey: key) }
        let deadline = ProcessInfo.processInfo.systemUptime + limit
        var status: Int32 = 0
        while true {
            // WNOWAIT keeps the process identity reserved until group cleanup.
            var info = siginfo_t()
            if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0, info.si_pid == pid {
                kill(-pid, SIGKILL); waitpid(pid, &status, 0)
                return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
            }
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                kill(-pid, SIGKILL); waitpid(pid, &status, 0)
                throw ModeError("Hook cancelled or exceeded its \(Int(limit))-second limit")
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

extension AppModel {
    func observeWorkOutcomes(now: Date) {
        for request in workRequests.records where request.state != .active && !observedWorkEnds.contains(request.id) {
            observedWorkEnds.insert(request.id)
            record("工作请求结束：\(request.spec.title) · \(request.state.rawValue)",
                   context: .init(kind: .request, requestIDs: [request.id], mode: active?.rawValue))
            guard let profile = requestProfiles.removeValue(forKey: request.id), let outcome = profile.outcome(for: request.state) else { continue }
            if outcome.notify { notificationHandler?("\(profile.name) · \(request.spec.title) · \(request.state.rawValue)") }
            guard let path = outcome.scriptPath else { continue }
            let epoch = workStopEpoch
            guard hooksMayRun, let approval = requestHookApprovals.removeValue(forKey: request.id), approval == profiles.approvals[profile.id.uuidString] else {
                record("结果脚本未执行：未启用、内容已变化或保护优先。")
                continue
            }
            Task { @MainActor [weak self] in
                guard let self, epoch == self.workStopEpoch, self.hooksMayRun else { return }
                do {
                    let script = try self.profiles.approvedScript(profile, path: path, expected: approval)
                    let code = try await self.policyHooks.run(script: script, sourcePath: path, record: request)
                    self.record("结果脚本结束：\(profile.name) · exit \(code)")
                } catch { self.record("结果脚本停止：" + error.localizedDescription) }
            }
        }
        let retained = Set(workRequests.records.map(\.id))
        observedWorkEnds.formIntersection(retained)
        requestProfiles = requestProfiles.filter { retained.contains($0.key) && !observedWorkEnds.contains($0.key) }
        requestHookApprovals = requestHookApprovals.filter { retained.contains($0.key) && !observedWorkEnds.contains($0.key) }
    }
    var hooksMayRun: Bool {
        !requestStopInProgress && !thermalProtectionRequired && !thermalCleanupPending
            && !(automation.batteryEnabled && battery.map { $0.onBattery && $0.percent <= automation.batteryThreshold } == true)
    }
}
