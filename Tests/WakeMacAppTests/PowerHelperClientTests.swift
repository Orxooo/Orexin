// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
import ServiceManagement
import WakeMacPower
@testable import WakeMac

private final class RecoveryService: NSObject, PowerServiceProtocol {
    private let lock = NSLock()
    private var armed = false
    var rejection: String?
    var recoveryArmed: Bool { lock.lock(); defer { lock.unlock() }; return armed }
    func checkCompatibility(_ version: Int, reply: @escaping (String?) -> Void) { reply(nil) }
    func setBackground(_ enabled: Bool, reply: @escaping (String?) -> Void) { reply(rejection) }
    func renew(reply: @escaping (String?) -> Void) { reply(rejection) }
    func prepareUnlockedWork(reply: @escaping (String?) -> Void) {
        lock.lock(); armed = rejection == nil; lock.unlock()
        reply(rejection)
    }
    func endUnlockedWork(reply: @escaping (String?) -> Void) {
        lock.lock(); armed = false; lock.unlock()
        reply(nil)
    }
}

private final class HelperEndpoint: NSObject, NSXPCListenerDelegate {
    let service = RecoveryService()
    let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []
    override init() { super.init(); listener.delegate = self; listener.resume() }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: PowerServiceProtocol.self)
        connection.exportedObject = service
        lock.lock(); connections.append(connection); lock.unlock()
        connection.resume()
        return true
    }
    func disconnect() { lock.lock(); let saved = connections; lock.unlock(); saved.forEach { $0.invalidate() } }
    func connect() -> NSXPCConnection { NSXPCConnection(listenerEndpoint: listener.endpoint) }
    deinit { listener.invalidate(); connections.forEach { $0.invalidate() } }
}

final class PowerHelperClientTests: XCTestCase {
    func testReachableHelperArmsRecoveryDespiteUnavailableRegistrationMetadata() async throws {
        guard SMAppService.daemon(plistName: PowerService.plistName).status != .enabled else {
            throw XCTSkip("This regression requires a caller without registered app metadata.")
        }
        let endpoint = HelperEndpoint()
        let client = PowerHelperClient(makeConnection: endpoint.connect)
        try await client.prepareUnlockedWork()
        XCTAssertTrue(endpoint.service.recoveryArmed)
        try await client.endUnlockedWork()
        XCTAssertFalse(endpoint.service.recoveryArmed)
    }

    func testHelperRejectionIsPreservedInsteadOfReportedAsMissingApproval() async {
        let endpoint = HelperEndpoint()
        endpoint.service.rejection = "Another client owns the recovery lease"
        let client = PowerHelperClient(makeConnection: endpoint.connect)
        do { try await client.prepareUnlockedWork(); XCTFail("Rejected recovery must not succeed") }
        catch { XCTAssertEqual(error.localizedDescription, "Another client owns the recovery lease") }
        XCTAssertFalse(endpoint.service.recoveryArmed)
    }

    func testConnectionFailureExplainsTheRequestedFeatureAndCanRecoverWithoutRestart() async throws {
        let endpoint = HelperEndpoint()
        var unavailable = true
        let client = PowerHelperClient(makeConnection: {
            if unavailable { throw NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid) }
            return endpoint.connect()
        })
        do { try await client.prepareUnlockedWork(); XCTFail("Unavailable helper must not succeed") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("保持未锁定"))
            XCTAssertFalse(error.localizedDescription.contains("桌面工作无需"))
        }
        unavailable = false
        try await client.prepareUnlockedWork()
        XCTAssertTrue(endpoint.service.recoveryArmed)
        try await client.endUnlockedWork()
    }
}

extension PowerHelperClientTests {
    func testStaleHelperIsReloadedBeforeStartingWork() async throws {
        let endpoint = HelperEndpoint()
        var unavailable = true
        var repairs = 0
        let client = PowerHelperClient(makeConnection: {
            if unavailable { throw NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid) }
            return endpoint.connect()
        }, recoverService: { repairs += 1; unavailable = false })
        try await client.prepareUnlockedWork()
        XCTAssertEqual(repairs, 1)
        XCTAssertTrue(endpoint.service.recoveryArmed)
        try await client.endUnlockedWork()
    }
    func testFailedReloadDoesNotLoopOrArmRecovery() async {
        let endpoint = HelperEndpoint()
        var repairs = 0
        let client = PowerHelperClient(makeConnection: {
            throw NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)
        }, recoverService: { repairs += 1 })
        do { try await client.prepareUnlockedWork(); XCTFail("Unreachable service must fail") }
        catch { XCTAssertTrue(error is PowerHelperConnectionFailure) }
        XCTAssertEqual(repairs, 1)
        XCTAssertFalse(endpoint.service.recoveryArmed)
    }
    func testLeaseRenewalNeverReloadsHelper() async {
        var repairs = 0
        let client = PowerHelperClient(makeConnection: {
            throw NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid)
        }, recoverService: { repairs += 1 })
        do { try await client.renew(); XCTFail("Missing lease must fail") } catch {}
        XCTAssertEqual(repairs, 0)
    }
}

extension PowerHelperClientTests {
    func testConnectionLossDuringHeldWorkDoesNotReloadService() async throws {
        let endpoint = HelperEndpoint()
        var repairs = 0
        var activeConnection: NSXPCConnection?
        let client = PowerHelperClient(makeConnection: {
            let connection = endpoint.connect(); activeConnection = connection; return connection
        }, recoverService: { repairs += 1 })
        try await client.setBackground(true)
        try XCTUnwrap(activeConnection).invalidate()
        do { try await client.prepareUnlockedWork(); XCTFail("Lost held connection must fail") } catch {}
        XCTAssertEqual(repairs, 0)
    }
    func testFeatureRejectionDoesNotReloadService() async {
        let endpoint = HelperEndpoint()
        endpoint.service.rejection = "Another client owns the recovery lease"
        var repairs = 0
        let client = PowerHelperClient(makeConnection: endpoint.connect, recoverService: { repairs += 1 })
        do { try await client.prepareUnlockedWork(); XCTFail("Must reject") }
        catch { XCTAssertEqual(error.localizedDescription, "Another client owns the recovery lease") }
        XCTAssertEqual(repairs, 0)
    }
}
