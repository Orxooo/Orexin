// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import Darwin

/// A PID and its kernel start time, scoped to the current user. No argv or environment.
public struct LocalProcessIdentity: Codable, Equatable, Sendable {
    public let pid: Int32
    public let seconds: UInt64
    public let microseconds: UInt64
    public static func capture(pid: Int32) -> Self? {
        guard let info = read(pid), info.pbi_uid == getuid(), info.pbi_status != UInt32(SZOMB) else { return nil }
        return .init(pid: pid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
    public var isAlive: Bool? {
        errno = 0
        guard let info = Self.read(pid) else { return errno == ESRCH || errno == ENOENT ? false : nil }
        return info.pbi_uid == getuid() && info.pbi_status != UInt32(SZOMB)
            && info.pbi_start_tvsec == seconds && info.pbi_start_tvusec == microseconds
    }
    private static func read(_ pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size ? info : nil
    }
}
