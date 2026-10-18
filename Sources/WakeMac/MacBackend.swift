// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import CoreGraphics
import IOKit
import WakeMacCore
import WakeMacPower
import os

actor MacBackend: ModeBackend {
    private let injectedCommand: (@Sendable (String, [String], TimeInterval) async throws -> String)?
    private let heartbeatInterval: UInt64
    private let preferences: UserDefaults
    private let allowsAuthentication: Bool
    init(command: (@Sendable (String, [String], TimeInterval) async throws -> String)? = nil,
         helper: any BackgroundLeaseClient = PowerHelperClient(), heartbeatInterval: UInt64 = 5_000_000_000,
         preferences: UserDefaults = .standard, allowsAuthentication: Bool = true) {
        injectedCommand = command; self.helper = helper; self.heartbeatInterval = max(1_000_000, heartbeatInterval)
        self.preferences = preferences; self.allowsAuthentication = allowsAuthentication
    }
    private func command(_ path: String, _ args: [String], timeout: TimeInterval = 20) async throws -> String {
        if let injectedCommand { return try await injectedCommand(path, args, timeout) }
        return try await Task.detached(priority: .userInitiated) { try CommandRunner.run(path, args, timeout: timeout) }.value
    }
    private func sleepDisabled() async throws -> Bool {
        let disabled: Bool?
        if injectedCommand != nil {
            disabled = SystemParsing.sleepDisabled(try await command("/usr/bin/pmset", ["-g"]))
        } else {
            disabled = SystemPowerReadback.sleepDisabled()
        }
        guard let disabled else { throw ModeError("无法读取系统防休眠状态。") }
        return disabled
    }
    private let assertion = NativeSleepAssertion()
    private let helper: any BackgroundLeaseClient
    private var backgroundRequested = false
    private var unlockedRequested = false
    private var heartbeat: Task<Void, Never>?
    private var leaseGeneration: UInt64 = 0
    private var leaseFailure: String?
    private let leaseLogger = Logger(subsystem: "com.orxooo.Orexin", category: "PowerLease")
    private func startHeartbeat() {
        let revision = leaseGeneration, interval = heartbeatInterval
        heartbeat = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) } catch { return }
                guard !Task.isCancelled, await self?.renewLease(generation: revision) == true else { return }
            }
        }
    }
    private func renewLease(generation revision: UInt64) async -> Bool {
        guard leaseGeneration == revision, backgroundRequested || unlockedRequested else { return false }
        let started = ProcessInfo.processInfo.systemUptime
        leaseLogger.debug("Lease renewal requested at \(started, privacy: .public)")
        do {
            try await helper.renew()
            guard leaseGeneration == revision, backgroundRequested || unlockedRequested else { return false }
            leaseLogger.debug("Lease renewal acknowledged at \(ProcessInfo.processInfo.systemUptime, privacy: .public)")
            return true
        } catch {
            guard leaseGeneration == revision, backgroundRequested || unlockedRequested else { return false }
            backgroundRequested = false
            let reason = error.localizedDescription
            var recoveryFailures: [String] = []
            if unlockedRequested {
                do { try await restoreUnlockedWork() } catch { recoveryFailures.append(error.localizedDescription) }
            }
            do { try assertion.release() } catch { recoveryFailures.append(error.localizedDescription) }
            leaseFailure = (recoveryFailures.isEmpty ? "工作会话已失效，已释放本应用的保活。\n" : "工作会话已失效；恢复未完成：\n" + recoveryFailures.joined(separator: "\n") + "\n") + reason
            leaseLogger.error("Lease renewal failed; native assertion released or failure retained")
            return false
        }
    }
    private func stopHeartbeat() async {
        leaseGeneration &+= 1
        let previous = heartbeat; heartbeat = nil
        previous?.cancel()
        // Drain an already-sent reply before changing the same XPC connection's
        // lease. A late failure must not invalidate a newly started session.
        await previous?.value
    }
    func snapshot() async throws -> Snapshot {
        if let leaseFailure { throw ModeError(leaseFailure) }
        let began = ProcessInfo.processInfo.systemUptime
        let power = try await sleepDisabled()
        let policy = try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        if let leaseFailure { throw ModeError(leaseFailure) }
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        if elapsed > 5 { leaseLogger.warning("Status readback took \(elapsed, privacy: .public) seconds; renewal runs independently") }
        return Snapshot(sleepDisabled: power, lockPolicy: SystemParsing.lockPolicy(policy),
                        idleSleepPrevented: assertion.active, displaySleepAllowed: true, backgroundLeaseActive: backgroundRequested)
    }
    func configurePower(_ mode: WorkMode) async throws {
        await stopHeartbeat()
        leaseFailure = nil
        if mode == .normal {
            try await releaseNormalPower()
            return
        }
        if mode != .background {
            try assertion.release()
            if backgroundRequested {
                do { try await helper.setBackground(false) }
                catch {
                    // An unapproved/unavailable helper cannot leave us in an
                    // error state when system readback already confirms sleep.
                    guard try await sleepDisabled() == false else { throw error }
                }
                backgroundRequested = false
            }
        }
        if mode == .background {
            backgroundRequested = true
            try await helper.setBackground(true)
        }
        if preferences.bool(forKey: "orexin.work.keepUnlocked"), !unlockedRequested {
            guard allowsAuthentication else { throw ModeError("Authorize unlocked work from the Orexin interface first") }
            guard let lockHelper = helper as? any ScreenLockLeaseClient else { throw ModeError("当前服务不支持临时锁屏策略。") }
            try await lockHelper.prepareUnlockedWork()
            unlockedRequested = true
            preferences.set(true, forKey: "orexin.UnlockedLeaseArmed")
            startHeartbeat()
            do {
                var password = try await UnlockedWorkAuthorization.requestPassword()
                defer { password.resetBytes(in: 0..<password.count) }
                guard unlockedRequested, leaseFailure == nil else { throw ModeError("服务会话已失效，请重新开始工作。") }
                try await helper.renew()
                try await Task.detached(priority: .userInitiated) { [password] in try UnlockedWorkAuthorization.disableScreenLock(password: password) }.value
                try await helper.renew()
                let lockState = try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"])
                guard SystemParsing.lockPolicy(lockState) == .off, leaseFailure == nil else { throw ModeError("未确认临时关闭锁定；已恢复密码保护。") }
            } catch {
                let reason = error
                try await restoreUnlockedWork()
                throw reason
            }
        }
        if heartbeat == nil, backgroundRequested || unlockedRequested { startHeartbeat() }
        let power = try await sleepDisabled()
        if let leaseFailure { throw ModeError(leaseFailure) }
        guard power == (mode == .background) else {
            throw ModeError("系统防休眠状态不一致。请先在其他保活程序中恢复休眠，再重新选择模式。")
        }
        if mode != .normal { try assertion.acquire() }
    }
    func prepareUnlockedWorkFromInterface() async throws {
        guard !unlockedRequested, let lockHelper = helper as? any ScreenLockLeaseClient else { throw ModeError("Unlocked work is already active or unsupported") }
        try await lockHelper.prepareUnlockedWork()
        unlockedRequested = true
        preferences.set(true, forKey: "orexin.UnlockedLeaseArmed")
        startHeartbeat()
    }
    func renewPendingUnlockedWork() async throws {
        guard unlockedRequested else { throw ModeError("Unlocked-work recovery lease ended") }
        try await helper.renew()
    }
    func verifyUnlockedWorkFromInterface() async throws {
        guard unlockedRequested else { throw ModeError("No pending unlocked-work recovery lease") }
        let policy = SystemParsing.lockPolicy(try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"]))
        guard policy == .off else { try await restoreUnlockedWork(); throw ModeError("Unlocked-work authorization did not finish") }
    }
    private func releaseNormalPower() async throws {
        var failures: [String] = []
        if unlockedRequested || preferences.bool(forKey: "orexin.UnlockedLeaseArmed") {
            do { try await restoreUnlockedWork() } catch { failures.append(error.localizedDescription) }
        }
        // Password recovery must not prevent either power inhibitor from being
        // released. Preserve failures so the caller cannot report false success.
        do { try assertion.release() } catch { failures.append(error.localizedDescription) }
        if backgroundRequested {
            do { try await helper.setBackground(false); backgroundRequested = false }
            catch {
                let helperError = error
                do {
                    if try await sleepDisabled() == false { backgroundRequested = false }
                    else { failures.append(helperError.localizedDescription) }
                } catch { failures.append(error.localizedDescription) }
            }
        }
        do {
            if try await sleepDisabled() != false {
                failures.append("系统防休眠状态不一致。请先在其他保活程序中恢复休眠，再重新选择模式。")
            }
        } catch { failures.append(error.localizedDescription) }
        if !failures.isEmpty { throw ModeError(failures.joined(separator: "\n")) }
    }
    private func restoreUnlockedWork() async throws {
        if let lockHelper = helper as? any ScreenLockLeaseClient {
            do { try await lockHelper.endUnlockedWork() } catch { /* Local tightening is also available during a service restart. */ }
        }
        _ = try await command("/usr/sbin/sysadminctl", ["-screenLock", "immediate", "-password", ""])
        let status = try await command("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        guard SystemParsing.lockPolicy(status) == .immediate else { throw ModeError("即时密码保护尚未恢复；服务会继续重试。") }
        unlockedRequested = false
        preferences.set(false, forKey: "orexin.UnlockedLeaseArmed")
    }
    func requestLockPolicy(_ policy: LockPolicy) async {
        guard allowsAuthentication else { return }
        await MainActor.run {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") { NSWorkspace.shared.open(url) }
        }
    }
    func sleepNow() async throws { _ = try await command("/usr/bin/pmset", ["sleepnow"]) }
    deinit { heartbeat?.cancel() }
}

struct DisplayState: Equatable {
    var lidClosed: Bool?
    var builtInAsleep: Bool?
    var sessionLocked: Bool?
    static func read() -> DisplayState {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        var lid: Bool?
        if root != 0 {
            lid = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            IOObjectRelease(root)
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        var asleep: Bool?
        if CGGetOnlineDisplayList(16, &ids, &count) == .success {
            if let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) { asleep = CGDisplayIsAsleep(id) != 0 }
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool
        return DisplayState(lidClosed: lid, builtInAsleep: asleep, sessionLocked: locked)
    }
}
