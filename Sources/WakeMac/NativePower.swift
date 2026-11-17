// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation
import IOKit.pwr_mgt
import WakeMacCore
import WakeMacPower

final class NativeSleepAssertion {
    private var id: IOPMAssertionID?
    var active: Bool? {
        guard let id else { return false }
        guard let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any],
              let level = properties[kIOPMAssertionLevelKey] as? NSNumber,
              properties[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleSystemSleep else { return nil }
        return level.uint32Value == UInt32(kIOPMAssertionLevelOn)
    }
    func acquire() throws {
        if active == true { return }
        try release()
        var created: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Orexin work session" as CFString, &created)
        guard result == kIOReturnSuccess else { throw ModeError(LF("无法建立原生保活会话（%d）。", result)) }
        id = created
        guard active == true else { throw ModeError("原生保活会话未通过系统回读核验。") }
    }
    func release() throws {
        guard let id else { return }
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw ModeError(LF("无法释放原生保活会话（%d）。", result)) }
        self.id = nil
    }
    deinit { if let id { IOPMAssertionRelease(id) } }
}

private final class ReplyGate {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Void, Error>) {
        lock.lock(); let saved = continuation; continuation = nil; lock.unlock()
        saved?.resume(with: result)
    }
}

private struct HelperRejection: Error { let message: String }
struct PowerHelperConnectionFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// Used only from MacBackend's actor. A connection owns one helper lease;
/// invalidating it causes the helper to restore sleep.
protocol BackgroundLeaseClient: AnyObject {
    func setBackground(_ enabled: Bool) async throws
    func renew() async throws
}
protocol ScreenLockLeaseClient: BackgroundLeaseClient {
    func prepareUnlockedWork() async throws
    func endUnlockedWork() async throws
}
final class PowerHelperClient: ScreenLockLeaseClient {
    private var connection: NSXPCConnection?
    private let makeConnection: () throws -> NSXPCConnection
    private let recoverService: (() async throws -> Void)?
    private var backgroundHeld = false
    private var unlockedHeld = false
    convenience init() {
        self.init(makeConnection: Self.signedConnection, recoverService: {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            if executable.lastPathComponent == "OrexinCore" {
                let application = try TaskServiceLauncher.executable(near: executable)
                _ = try await Task.detached { try CommandRunner.run(application.path, ["--check-power-helper"], timeout: 20) }.value
            } else {
                try await PowerHelperLifecycle.shared.reload()
            }
        })
    }
    private static func signedConnection() throws -> NSXPCConnection {
        let requirement = try PowerService.peerRequirement(identifier: PowerService.identifier)
        let connection = NSXPCConnection(machServiceName: PowerService.identifier, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        return connection
    }
    init(makeConnection: @escaping () throws -> NSXPCConnection, recoverService: (() async throws -> Void)? = nil) {
        self.makeConnection = makeConnection; self.recoverService = recoverService
    }
    func setBackground(_ enabled: Bool) async throws {
        if enabled { try await ensureReady() }
        try await request(context: "无法更改合盖运行状态。") { service, reply in service.setBackground(enabled, reply: reply) }
        backgroundHeld = enabled
    }
    func renew() async throws {
        try await request(context: "无法续约工作会话。") { service, reply in service.renew(reply: reply) }
    }
    func prepareUnlockedWork() async throws {
        try await ensureReady(context: "无法开始「工作时保持未锁定」。")
        try await request(context: "无法开始「工作时保持未锁定」。") { service, reply in service.prepareUnlockedWork(reply: reply) }
        unlockedHeld = true
    }
    func endUnlockedWork() async throws {
        try await request(context: "无法结束「保持未锁定」恢复会话。") { service, reply in service.endUnlockedWork(reply: reply) }
        unlockedHeld = false
    }
    /// Probe before acquiring a lease. Never reload a service holding our work.
    func ensureReady(context: String = "无法核验系统辅助服务。") async throws {
        do { try await probe(context: context) }
        catch let failure as PowerHelperConnectionFailure {
            guard !backgroundHeld, !unlockedHeld, let recoverService else { throw failure }
            try await recoverService()
            try await probe(context: context)
        }
    }
    private func probe(context: String) async throws {
        try await request(context: context, timeoutInterval: 2) { service, reply in
            service.checkCompatibility(1, reply: reply)
        }
    }
    private func request(context: String, timeoutInterval: Double = 8, _ call: (PowerServiceProtocol, @escaping (String?) -> Void) -> Void) async throws {
        do {
            // Registration metadata is process-relative and may lag approval.
            // The signed XPC peer's reply is authoritative; never veto it using
            // SMAppService.status from the long-running task-service process.
            let connection: NSXPCConnection
            if let current = self.connection { connection = current }
            else {
                connection = try makeConnection()
                connection.remoteObjectInterface = NSXPCInterface(with: PowerServiceProtocol.self)
                connection.resume(); self.connection = connection
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ReplyGate(continuation)
                let timeout = DispatchWorkItem {
                    gate.finish(.failure(ModeError("系统辅助服务响应超时；已断开连接以恢复休眠。")))
                    connection.invalidate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
                guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                    timeout.cancel(); gate.finish(.failure(error))
                }) as? PowerServiceProtocol else {
                    timeout.cancel(); gate.finish(.failure(ModeError("无法连接系统辅助服务。"))); return
                }
                call(service) { error in
                    timeout.cancel()
                    gate.finish(error.map { .failure(HelperRejection(message: $0)) } ?? .success(()))
                }
            }
        } catch {
            connection?.invalidate(); connection = nil
            if let rejection = error as? HelperRejection { throw ModeError(rejection.message) }
            throw PowerHelperConnectionFailure(reason: context + "\n系统辅助服务连接失败。请在偏好设置中启用并在系统设置中批准；若已批准，请重试。\n" + error.localizedDescription)
        }
    }
    deinit { connection?.invalidate() }
}
