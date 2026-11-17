// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import WakeMacCore
@testable import WakeMac

private actor AuthenticationTestStore: UnlockedWorkCredentialStore {
    var value: Data?
    var writes = 0
    var removals = 0
    init(_ value: Data? = nil) { self.value = value }
    func load() -> Data? { value }
    func save(_ password: Data) { value = password; writes += 1 }
    func delete() { value = nil; removals += 1 }
    func counts() -> (Int, Int) { (writes, removals) }
}

@MainActor final class UnlockedWorkAuthenticationTests: XCTestCase {
    private func credentials(_ store: AuthenticationTestStore) async throws -> UnlockedWorkCredentials {
        let name = "Orexin.AuthenticationTests." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        addTeardownBlock { prefs.removePersistentDomain(forName: name) }
        let controller = UnlockedWorkCredentials(preferences: prefs, store: store)
        try await controller.setEnabled(true)
        return controller
    }
    func testRememberedCredentialAvoidsPromptAndStillVerifies() async throws {
        let store = AuthenticationTestStore(Data("synthetic\n".utf8))
        let controller = try await credentials(store)
        var verified = false
        try await UnlockedWorkAuthentication.authorize(credentials: controller,
            requestPassword: { XCTFail("Should use the saved credential"); return Data() },
            renew: {}, apply: { XCTAssertEqual($0, Data("synthetic\n".utf8)) }, verify: { verified = true })
        XCTAssertTrue(verified)
        let counts = await store.counts()
        XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 0)
    }
    func testRejectedSavedCredentialPromptsOnceAndSavesOnlyAfterVerification() async throws {
        let store = AuthenticationTestStore(Data("outdated-synthetic\n".utf8))
        let controller = try await credentials(store)
        var prompts = 0, applies = 0
        try await UnlockedWorkAuthentication.authorize(credentials: controller,
            requestPassword: { prompts += 1; return Data("updated-synthetic\n".utf8) }, renew: {},
            apply: { _ in applies += 1; if applies == 1 { throw UnlockedWorkAuthenticationError.rejected } },
            verify: { let counts = await store.counts(); XCTAssertEqual(counts.0, 0) })
        let counts = await store.counts()
        XCTAssertEqual(prompts, 1); XCTAssertEqual(applies, 2)
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testTransportFailurePreservesCredentialAndNeverPrompts() async throws {
        let store = AuthenticationTestStore(Data("synthetic\n".utf8))
        let controller = try await credentials(store)
        do {
            try await UnlockedWorkAuthentication.authorize(credentials: controller,
                requestPassword: { XCTFail("Transport failure must not prompt"); return Data() },
                renew: { throw ModeError("synthetic connection failure") }, apply: { _ in XCTFail() }, verify: { XCTFail() })
            XCTFail("Expected failure")
        } catch {}
        let counts = await store.counts()
        XCTAssertEqual(counts.1, 0)
    }
    func testFailedFinalVerificationNeverSavesCredential() async throws {
        let store = AuthenticationTestStore()
        let controller = try await credentials(store)
        do {
            try await UnlockedWorkAuthentication.authorize(credentials: controller,
                requestPassword: { Data("synthetic\n".utf8) }, renew: {}, apply: { _ in },
                verify: { throw ModeError("synthetic lease verification failure") })
            XCTFail("Expected failure")
        } catch {}
        let counts = await store.counts()
        XCTAssertEqual(counts.0, 0)
    }
    func testSecondAuthenticationRejectionDoesNotLoopOrSave() async throws {
        let store = AuthenticationTestStore(Data("old-synthetic\n".utf8))
        let controller = try await credentials(store)
        var prompts = 0, applies = 0
        do {
            try await UnlockedWorkAuthentication.authorize(credentials: controller,
                requestPassword: { prompts += 1; return Data("synthetic\n".utf8) }, renew: {},
                apply: { _ in applies += 1; throw UnlockedWorkAuthenticationError.rejected }, verify: { XCTFail() })
            XCTFail("Expected failure")
        } catch {}
        XCTAssertEqual(prompts, 1); XCTAssertEqual(applies, 2)
        let counts = await store.counts()
        XCTAssertEqual(counts.0, 0)
    }
}
