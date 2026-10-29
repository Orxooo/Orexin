// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import WakeMacCore
@testable import WakeMac

private actor RestartLockSystem: ScreenLockLeaseClient {
    var immediate = false
    var armed = false
    var prepares = 0
    private var holdStatus = false
    private var heldStatus: (CheckedContinuation<String, Never>, String)?
    func setBackground(_ enabled: Bool) {}
    func renew() throws { if !armed { throw ModeError("临时锁屏会话已失效。") } }
    func prepareUnlockedWork() throws {
        guard immediate else { throw ModeError("临时保持未锁定需要先将 macOS 密码要求设为「立即」。") }
        prepares += 1; armed = true
    }
    func endUnlockedWork() { armed = false; immediate = true }
    func authorize() { immediate = false }
    func holdNextStatus() { holdStatus = true }
    func statusIsHeld() -> Bool { heldStatus != nil }
    func resumeStatus() { if let held = heldStatus { heldStatus = nil; held.0.resume(returning: held.1) } }
    func command(_ path: String, _ args: [String]) async -> String {
        if path.hasSuffix("sysadminctl") {
            if args.contains("immediate") { immediate = true }
            let result = immediate ? "screenLock delay is immediate" : "screenLock is off"
            if args == ["-screenLock", "status"], holdStatus {
                holdStatus = false
                return await withCheckedContinuation { heldStatus = ($0, result) }
            }
            return result
        }
        return "SleepDisabled 0"
    }
}

@MainActor final class RestartAuthorizationTests: XCTestCase {
    private final class Effects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport { .init(displayAssertionActive: working && choices.preventDisplaySleep) }
        func release() {}
    }
    private func exercise(cancel: Bool) async throws {
        let name = "Orexin.RestartAuthorization." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(true, forKey: "orexin.work.keepUnlocked")
        let system = RestartLockSystem()
        let backend = MacBackend(command: { path, args, _ in await system.command(path, args) }, helper: system, preferences: prefs, allowsAuthentication: false)
        let service = AppModel(backend: backend, preferences: prefs, sessionEffects: Effects())
        service.isTaskService = true; service.serviceInfo = TaskServiceInfo(stateDirectory: "/tmp")
        service.active = .normal; service.snapshot = try await backend.snapshot()
        let path = "/tmp/orxa-" + UUID().uuidString.prefix(8) + "/control.sock"
        let server = try LocalControlServer(path: path) { await service.handleTaskControl($0) }
        defer { server.stop() }
        let client = AppModel(backend: ServiceModeBackend(path: path), preferences: prefs, sessionEffects: Effects())
        client.serviceSocket = path; client.workScreen.select(.systemIdle, for: .desk)
        var prompts = 0
        client.requestUnlockedWorkPassword = {
            prompts += 1
            if cancel { throw ModeError("已取消授权，系统密码要求未更改。") }
            return Data("test-only\n".utf8)
        }
        client.disableUnlockedWorkScreenLock = { _ in await system.authorize() }
        await client.refresh()
        XCTAssertEqual(client.snapshot?.lockPolicy, .off)
        await client.choose(.desk)
        XCTAssertEqual(prompts, 1, "A cold service must not mistake lock-off readback for a live authorization")
        if cancel {
            XCTAssertTrue(client.error)
            XCTAssertTrue(service.workRequests.active.isEmpty)
        } else {
            XCTAssertFalse(client.error, client.message)
            XCTAssertTrue(client.verifiedWork)
            XCTAssertEqual(service.workRequests.active.count, 1)
            await client.setWorkScreenBehavior(.normalBrightness)
            XCTAssertFalse(client.error, client.message)
            XCTAssertEqual(prompts, 1, "A verified live lease must survive ordinary display changes")
            await client.choose(.normal)
        }
        let immediate = await system.immediate, armed = await system.armed, prepares = await system.prepares
        XCTAssertTrue(immediate); XCTAssertFalse(armed); XCTAssertEqual(prepares, 1)
        XCTAssertFalse(prefs.bool(forKey: "orexin.UnlockedLeaseArmed"))
    }
    func testColdServiceWithLockAlreadyOffReauthorizesAndReusesVerifiedLease() async throws { try await exercise(cancel: false) }
    func testCancelledRestartAuthorizationRestoresProtectionWithoutStartingWork() async throws { try await exercise(cancel: true) }
    func testColdStartupRestoresProtectionEvenWhenPreviousLeaseMarkerWasCleared() async throws {
        let name = "Orexin.ColdStartup." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(true, forKey: "orexin.work.keepUnlocked")
        let system = RestartLockSystem()
        let backend = MacBackend(command: { path, args, _ in await system.command(path, args) }, helper: system, preferences: prefs, allowsAuthentication: false)
        try await backend.configurePower(.normal)
        let snapshot = try await backend.snapshot(), prepares = await system.prepares
        XCTAssertEqual(snapshot.lockPolicy, .immediate)
        XCTAssertEqual(prepares, 0)
        XCTAssertFalse(prefs.bool(forKey: "orexin.UnlockedLeaseArmed"))
    }
    func testDisablingOptionalUnlockedWorkRestoresStaleLockOffBeforeSavingPreference() async throws {
        let name = "Orexin.DisableUnlocked." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(true, forKey: "orexin.work.keepUnlocked")
        let system = RestartLockSystem()
        let backend = MacBackend(command: { path, args, _ in await system.command(path, args) }, helper: system, preferences: prefs, allowsAuthentication: false)
        let model = AppModel(backend: backend, preferences: prefs, sessionEffects: Effects())
        model.active = .normal; model.snapshot = try await backend.snapshot()
        await model.setUnlockedWork(false)
        XCTAssertFalse(model.error, model.message)
        XCTAssertFalse(prefs.bool(forKey: "orexin.work.keepUnlocked"))
        let immediate = await system.immediate
        XCTAssertTrue(immediate)
    }

    private func exerciseStaleRead(verification: Bool) async throws {
        let name = "Orexin.StaleAuthorization." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(true, forKey: "orexin.work.keepUnlocked")
        let system = RestartLockSystem()
        let backend = MacBackend(command: { path, args, _ in await system.command(path, args) }, helper: system, preferences: prefs, allowsAuthentication: false)
        try await backend.prepareUnlockedWorkFromInterface(); await system.authorize()
        if !verification { try await backend.verifyUnlockedWorkFromInterface() }
        await system.holdNextStatus()
        let pending = Task {
            if verification { try await backend.verifyUnlockedWorkFromInterface(); return true }
            return try await backend.unlockedWorkAuthorizationIsActive()
        }
        for _ in 0..<100 where !(await system.statusIsHeld()) { try await Task.sleep(for: .milliseconds(10)) }
        let held = await system.statusIsHeld(); XCTAssertTrue(held)
        try await backend.configurePower(.normal)
        await system.resumeStatus()
        if verification {
            do { _ = try await pending.value; XCTFail("Cleanup must invalidate a delayed authorization verification") } catch {}
        } else { let active = try await pending.value; XCTAssertFalse(active) }
        do { try await backend.configurePower(.desk); XCTFail("A stale read must not authorize new work") } catch {}
        try await backend.configurePower(.normal)
    }
    func testCleanupInvalidatesDelayedAuthorizationVerification() async throws { try await exerciseStaleRead(verification: true) }
    func testCleanupInvalidatesDelayedAuthorizationReuse() async throws { try await exerciseStaleRead(verification: false) }
}
