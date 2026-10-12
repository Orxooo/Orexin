// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import WakeMacCore

final class SystemScreenLockRecovery: ScreenLockRecoverySwitch {
    private struct Journal: Codable { let userID: UInt32; let deadline: Date }
    private let url = URL(fileURLWithPath: "/var/db/com.orxooo.Orexin.ScreenLockLease")
    private var pending: Journal?
    private var recoveryUptime: TimeInterval?

    init() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0 else { throw ModeError("锁屏恢复文件所有者无效。") }
            pending = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
            // Wait out a bounded in-flight authentication after a helper restart.
            if let saved = pending {
                pending = Journal(userID: saved.userID, deadline: min(saved.deadline, Date().addingTimeInterval(35)))
                recoveryUptime = ProcessInfo.processInfo.systemUptime + max(0, min(35, saved.deadline.timeIntervalSinceNow))
            }
        }
    }
    private func command(userID: UInt32, arguments: [String]) throws -> String {
        guard userID >= 500 else { throw ModeError("锁屏恢复用户无效。") }
        return try CommandRunner.run("/bin/launchctl", ["asuser", String(userID), "/usr/bin/sudo", "-n", "-u", "#\(userID)", "/usr/sbin/sysadminctl"] + arguments, timeout: 5)
    }
    func isImmediate(userID: UInt32) throws -> Bool {
        SystemParsing.lockPolicy(try command(userID: userID, arguments: ["-screenLock", "status"])) == .immediate
    }
    func armRecovery(userID: UInt32, seconds: TimeInterval) throws {
        let journal = Journal(userID: userID, deadline: Date().addingTimeInterval(seconds))
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        pending = journal
        recoveryUptime = ProcessInfo.processInfo.systemUptime + seconds
    }
    func restoreImmediate(userID: UInt32) throws {
        _ = try command(userID: userID, arguments: ["-screenLock", "immediate", "-password", ""])
        guard try isImmediate(userID: userID) else { throw ModeError("系统尚未恢复即时密码保护。") }
        if pending?.userID == userID {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            pending = nil
            recoveryUptime = nil
        }
    }
    func recoverIfDue() throws {
        if let pending, let recoveryUptime, ProcessInfo.processInfo.systemUptime >= recoveryUptime { try restoreImmediate(userID: pending.userID) }
    }
}
