// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation
import IOKit.ps
import WakeMacCore
import WakeMacPower

private final class SystemSleepSwitch: SleepSwitch {
    // A root-owned journal allows launchd's restarted helper to undo its own
    // setting after a crash. Never reset an unrelated pre-existing inhibitor.
    private let journal = URL(fileURLWithPath: "/var/db/com.orxooo.Orexin.PowerLease")
    func powerSource() -> SleepPowerSource? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return nil }
        switch source {
        case kIOPSACPowerValue: return .external
        case kIOPSBatteryPowerValue: return .battery
        default: return nil
        }
    }
    func read() throws -> Bool {
        guard let disabled = SystemPowerReadback.sleepDisabled() else { throw ModeError("无法读取系统防休眠状态。") }
        return disabled
    }
    func setDisabled(_ enabled: Bool) throws {
        if enabled {
            try Data("Orexin\n".utf8).write(to: journal, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        }
        _ = try CommandRunner.run("/usr/bin/pmset", ["-a", "disablesleep", enabled ? "1" : "0"], timeout: 5)
        guard try read() == enabled else { throw ModeError("系统电源状态与请求不一致。") }
        if !enabled && FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
    }
    func recoverJournal() throws {
        if FileManager.default.fileExists(atPath: journal.path) { try setDisabled(false) }
    }
}

private final class ClientSession: NSObject, PowerServiceProtocol {
    let id = UUID()
    let host: HelperHost
    let userID: UInt32
    private var backgroundHeld = false
    private var screenLockHeld = false
    init(host: HelperHost, userID: UInt32) { self.host = host; self.userID = userID }
    func setBackground(_ enabled: Bool, reply: @escaping (String?) -> Void) {
        host.queue.async {
            do {
                if enabled { try self.host.lease.begin(owner: self.id, uptime: ProcessInfo.processInfo.systemUptime) }
                else { try self.host.lease.end(owner: self.id) }
                self.backgroundHeld = enabled
                reply(nil)
            } catch { reply(error.localizedDescription) }
        }
    }
    func renew(reply: @escaping (String?) -> Void) {
        host.queue.async {
            do {
                let uptime = ProcessInfo.processInfo.systemUptime
                guard self.backgroundHeld || self.screenLockHeld else { throw ModeError("服务会话已失效，请重新开始工作。") }
                if self.backgroundHeld { try self.host.lease.renew(owner: self.id, uptime: uptime) }
                if self.screenLockHeld { try self.host.screenLock.renew(owner: self.id, uptime: uptime) }
                reply(nil)
            }
            catch { reply(error.localizedDescription) }
        }
    }
    func prepareUnlockedWork(reply: @escaping (String?) -> Void) {
        host.queue.async {
            do { try self.host.screenLock.begin(owner: self.id, userID: self.userID, uptime: ProcessInfo.processInfo.systemUptime); self.screenLockHeld = true; reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func endUnlockedWork(reply: @escaping (String?) -> Void) {
        host.queue.async {
            do { try self.host.screenLock.end(owner: self.id); self.screenLockHeld = false; reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
}

private final class HelperHost: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "Orexin.PowerLease")
    let lease: SleepLease
    let screenLock: ScreenLockLease
    let requirement: String
    var watchdog: DispatchSourceTimer?
    init(power: SystemSleepSwitch, lockRecovery: SystemScreenLockRecovery, requirement: String) {
        lease = SleepLease(power: power); self.requirement = requirement
        screenLock = ScreenLockLease(recovery: lockRecovery)
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            do { try self?.lease.expire(uptime: ProcessInfo.processInfo.systemUptime) }
            catch { fputs("Orexin: sleep recovery failed; retrying.\n", stderr) }
            do { try self?.screenLock.expire(uptime: ProcessInfo.processInfo.systemUptime); try lockRecovery.recoverIfDue() }
            catch { fputs("Orexin: screen lock recovery failed; retrying.\n", stderr) }
        }
        timer.resume(); watchdog = timer
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let session = ClientSession(host: self, userID: connection.effectiveUserIdentifier)
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: PowerServiceProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self] in
            self?.queue.async {
                do { try self?.lease.end(owner: session.id) }
                catch { fputs("Orexin: disconnected-client recovery failed; watchdog will retry.\n", stderr) }
                self?.screenLock.abandon(owner: session.id, uptime: ProcessInfo.processInfo.systemUptime)
            }
        }
        connection.resume()
        return true
    }
}

@main struct HelperMain {
    static func main() {
        guard getuid() == 0 else { fputs("OrexinPowerHelper must be launched by the approved system service.\n", stderr); exit(1) }
        do {
            let power = SystemSleepSwitch()
            try power.recoverJournal()
            let host = HelperHost(power: power, lockRecovery: try SystemScreenLockRecovery(), requirement: try PowerService.peerRequirement(identifier: PowerService.appIdentifier))
            let listener = NSXPCListener(machServiceName: PowerService.identifier)
            listener.delegate = host; listener.resume()
            withExtendedLifetime((host, listener)) { RunLoop.current.run() }
        } catch { fputs("Orexin: helper startup or recovery failed.\n", stderr); exit(1) }
    }
}
