// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ServiceManagement
import WakeMacCore
import WakeMacPower

/// Shares one reload across concurrent connection attempts in this process.
actor PowerHelperLifecycle {
    static let shared = PowerHelperLifecycle()
    private var reloading: Task<Void, Error>?
    func reload() async throws {
        if let reloading { return try await reloading.value }
        let task = Task {
            _ = try PowerService.peerRequirement(identifier: PowerService.identifier)
            let service = SMAppService.daemon(plistName: PowerService.plistName)
            guard service.status != .requiresApproval else {
                throw ModeError("请在系统设置 → 登录项与扩展中批准 Orexin 辅助服务。")
            }
            if service.status == .enabled { try await service.unregister() }
            try await Self.registerAfterUnregister(register: { try service.register() },
                approvalRequired: { service.status == .requiresApproval })
            guard service.status == .enabled else {
                throw ModeError("辅助服务已重新登记，请在系统设置 → 登录项与扩展中完成批准。")
            }
        }
        reloading = task
        defer { reloading = nil }
        try await task.value
    }
    /// ServiceManagement can briefly return EPERM while an old registration is retiring.
    static func registerAfterUnregister(register: () throws -> Void, approvalRequired: () -> Bool,
        wait: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) async throws {
        for attempt in 0..<5 {
            do { try register(); return }
            catch {
                guard attempt < 4, !approvalRequired() else { throw error }
                try await wait(250_000_000 << attempt)
            }
        }
    }
    func prepareUpdate() async throws {
        let service = SMAppService.daemon(plistName: PowerService.plistName)
        if service.status == .enabled { try await service.unregister() }
    }
}
