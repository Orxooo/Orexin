// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation

public enum SleepPowerSource: Equatable { case battery, external }

public protocol SleepSwitch {
    func powerSource() -> SleepPowerSource?
    func read() throws -> Bool
    func setDisabled(_ enabled: Bool) throws
}

public extension SleepSwitch { func powerSource() -> SleepPowerSource? { nil } }

/// A single client's temporary demand for the global sleep switch.
/// All calls are serialized by the helper. Failed recovery retains ownership
/// so the watchdog can retry rather than silently abandon a disabled system.
public final class SleepLease {
    private let power: any SleepSwitch
    private var owner: UUID?
    private var expires: TimeInterval?
    private var changedSwitch = false
    public init(power: any SleepSwitch) { self.power = power }
    public func begin(owner client: UUID, uptime: TimeInterval) throws {
        if let owner {
            guard owner == client else { throw ModeError("另一个 Orexin 实例正在使用合盖服务。") }
        }
        owner = client; expires = uptime + 30
        try maintainPrevention()
    }
    public func renew(owner client: UUID, uptime: TimeInterval) throws {
        guard owner == client, let expires, uptime < expires else { throw ModeError("合盖会话已失效，请重新选择工作模式。") }
        try maintainPrevention()
        self.expires = uptime + 30
    }
    public func end(owner client: UUID) throws {
        guard owner == client else { return }
        try restore()
    }
    public func expire(uptime: TimeInterval) throws {
        guard let expires else { return }
        if uptime >= expires { try restore() }
        else { try maintainPrevention() }
    }
    private func maintainPrevention() throws {
        if try !power.read() {
            changedSwitch = true
            try power.setDisabled(true)
        }
        guard try power.read() else { throw ModeError("合盖防休眠未通过系统回读核验。") }
    }
    private func restore() throws {
        if changedSwitch {
            try power.setDisabled(false)
            guard try !power.read() else { throw ModeError("恢复休眠未通过系统回读核验。") }
        }
        owner = nil; expires = nil; changedSwitch = false
    }
}
