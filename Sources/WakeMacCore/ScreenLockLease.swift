// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

public protocol ScreenLockRecoverySwitch {
    func isImmediate(userID: UInt32) throws -> Bool
    func armRecovery(userID: UInt32, seconds: TimeInterval) throws
    func restoreImmediate(userID: UInt32) throws
}

/// The helper only arms recovery and restores password protection. Disabling
/// it requires the user's separate authentication in the application.
public final class ScreenLockLease {
    private let recovery: any ScreenLockRecoverySwitch
    private var owner: UUID?
    private var userID: UInt32?
    private var expires: TimeInterval?
    public init(recovery: any ScreenLockRecoverySwitch) { self.recovery = recovery }
    public func begin(owner client: UUID, userID: UInt32, uptime: TimeInterval) throws {
        if let owner {
            guard owner == client, self.userID == userID else { throw ModeError("另一个 Orexin 实例正在使用临时锁屏策略。") }
            try renew(owner: client, uptime: uptime)
            return
        }
        guard userID != 0, try recovery.isImmediate(userID: userID) else {
            throw ModeError("临时保持未锁定需要先将 macOS 密码要求设为「立即」。")
        }
        try recovery.armRecovery(userID: userID, seconds: 35)
        owner = client; self.userID = userID; expires = uptime + 30
    }
    public func renew(owner client: UUID, uptime: TimeInterval) throws {
        guard owner == client, let userID, let expires, uptime < expires else { throw ModeError("临时锁屏会话已失效。") }
        try recovery.armRecovery(userID: userID, seconds: 35)
        self.expires = uptime + 30
    }
    public func owns(_ client: UUID) -> Bool { owner == client }
    public func abandon(owner client: UUID, uptime: TimeInterval) {
        guard owner == client else { return }
        // Give the bounded authentication child time to exit before recovery.
        expires = uptime + 10
    }
    public func end(owner client: UUID) throws {
        guard owner == client else { return }
        try restore()
    }
    public func expire(uptime: TimeInterval) throws {
        if let expires, uptime >= expires { try restore() }
    }
    private func restore() throws {
        guard let userID else { return }
        try recovery.restoreImmediate(userID: userID)
        guard try recovery.isImmediate(userID: userID) else { throw ModeError("恢复即时密码保护未通过系统核验。") }
        owner = nil; self.userID = nil; expires = nil
    }
}
