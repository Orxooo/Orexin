// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import WakeMacCore
import Security
@testable import WakeMac

private actor MemoryCredentialStore: UnlockedWorkCredentialStore {
    var value: Data?
    var saves = 0
    var deletes = 0
    var failDelete = false
    var failSave = false
    var failLoad = false
    init(_ value: Data? = nil) { self.value = value }
    func load() throws -> Data? {
        if failLoad { throw ModeError("synthetic read failure") }
        return value
    }
    func save(_ password: Data) throws {
        if failSave { throw ModeError("synthetic save failure") }
        value = password; saves += 1
    }
    func delete() throws {
        if failDelete { throw ModeError("synthetic delete failure") }
        value = nil; deletes += 1
    }
    func setFailures(delete: Bool = false, save: Bool = false, load: Bool = false) {
        failDelete = delete; failSave = save; failLoad = load
    }
    func counts() -> (saves: Int, deletes: Int) { (saves, deletes) }
}

@MainActor final class UnlockedWorkCredentialTests: XCTestCase {
    private func preferences() -> UserDefaults {
        let name = "Orexin.CredentialTests." + UUID().uuidString
        let prefs = UserDefaults(suiteName: name)!
        addTeardownBlock { prefs.removePersistentDomain(forName: name) }
        return prefs
    }

    func testSecurityStoreRoundTripInDisposableKeychain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orexin-keychain-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("disposable.keychain").path
        let keychainPassword = "task-owned-synthetic-keychain-password"
        var keychain: SecKeychain?
        let created = keychainPassword.withCString { password in
            SecKeychainCreate(path, UInt32(strlen(password)), password, false, nil, &keychain)
        }
        XCTAssertEqual(created, errSecSuccess)
        let disposable = try XCTUnwrap(keychain)
        defer { XCTAssertEqual(SecKeychainDelete(disposable), errSecSuccess) }
        let store = KeychainUnlockedWorkCredentialStore(testKeychain: disposable)
        let secret = Data("task-owned-synthetic-secret\n".utf8)
        try await store.save(secret)
        let first = try await store.load()
        XCTAssertEqual(first, secret)
        let replacement = Data("replacement-synthetic-secret\n".utf8)
        try await store.save(replacement)
        let updated = try await store.load()
        XCTAssertEqual(updated, replacement)
        try await store.delete()
        let removed = try await store.load()
        XCTAssertNil(removed)
        try await store.delete()
    }

    func testDefaultOffPromptsAndDoesNotSave() async throws {
        let store = MemoryCredentialStore(Data("old-synthetic\n".utf8))
        let credentials = UnlockedWorkCredentials(preferences: preferences(), store: store)
        XCTAssertFalse(credentials.enabled)
        var prompts = 0
        let candidate = try await credentials.credential { prompts += 1; return Data("synthetic\n".utf8) }
        XCTAssertEqual(candidate.source, .interactive)
        await credentials.authenticated(candidate)
        let counts = await store.counts()
        XCTAssertEqual(counts.saves, 0); XCTAssertEqual(prompts, 1)
    }

    func testSaveOnlyAfterVerifiedAuthenticationThenReuse() async throws {
        let prefs = preferences(), store = MemoryCredentialStore()
        let credentials = UnlockedWorkCredentials(preferences: prefs, store: store)
        try await credentials.setEnabled(true)
        let candidate = try await credentials.credential { Data("synthetic\n".utf8) }
        let before = await store.counts()
        XCTAssertEqual(before.saves, 0)
        await credentials.authenticated(candidate)
        let saved = try await credentials.credential { XCTFail("Remembered password should avoid prompting"); return Data() }
        XCTAssertEqual(saved.source, .remembered)
        XCTAssertEqual(saved.password, candidate.password)
        await credentials.authenticated(saved)
        let counts = await store.counts()
        XCTAssertEqual(counts.saves, 1)
        XCTAssertTrue(prefs.bool(forKey: UnlockedWorkCredentials.preferenceKey))
        XCTAssertFalse(prefs.dictionaryRepresentation().values.contains { ($0 as? Data) == candidate.password })
    }

    func testDisableDeletesAndDoesNotResaveOldCandidate() async throws {
        let store = MemoryCredentialStore()
        let credentials = UnlockedWorkCredentials(preferences: preferences(), store: store)
        try await credentials.setEnabled(true)
        let candidate = try await credentials.credential { Data("synthetic\n".utf8) }
        await credentials.authenticated(candidate)
        try await credentials.setEnabled(false)
        try await credentials.setEnabled(true)
        await credentials.authenticated(candidate)
        let remaining = try await store.load(), counts = await store.counts()
        XCTAssertNil(remaining); XCTAssertEqual(counts.saves, 1)
    }

    func testExternalDisableBeforeAuthenticationPreventsSave() async throws {
        let prefs = preferences(), store = MemoryCredentialStore()
        let credentials = UnlockedWorkCredentials(preferences: prefs, store: store)
        try await credentials.setEnabled(true)
        let candidate = try await credentials.credential { Data("synthetic\n".utf8) }
        prefs.set(false, forKey: UnlockedWorkCredentials.preferenceKey)
        await credentials.authenticated(candidate)
        let counts = await store.counts()
        XCTAssertEqual(counts.saves, 0)
    }

    func testRejectedStoredPasswordDeletesBeforeInteractiveFallback() async throws {
        let store = MemoryCredentialStore(Data("expired-synthetic\n".utf8))
        let credentials = UnlockedWorkCredentials(preferences: preferences(), store: store)
        try await credentials.setEnabled(true)
        let saved = try await credentials.credential { XCTFail("Unexpected prompt"); return Data() }
        XCTAssertEqual(saved.source, .remembered)
        try await credentials.invalidateRememberedCredential()
        var prompts = 0
        let fallback = try await credentials.credential { prompts += 1; return Data("new-synthetic\n".utf8) }
        XCTAssertEqual(fallback.source, .interactive); XCTAssertEqual(prompts, 1)
    }

    func testDeletionFailureKeepsEnabledAndReportsFailure() async throws {
        let store = MemoryCredentialStore()
        let credentials = UnlockedWorkCredentials(preferences: preferences(), store: store)
        try await credentials.setEnabled(true)
        await store.setFailures(delete: true)
        do { try await credentials.setEnabled(false); XCTFail("Deletion must fail") }
        catch { XCTAssertEqual(error.localizedDescription, "synthetic delete failure") }
        XCTAssertTrue(credentials.enabled); XCTAssertFalse(credentials.busy)
        XCTAssertEqual(credentials.message, "synthetic delete failure")
    }

    func testReadFailureAllowsPromptAndSaveFailureIsVisible() async throws {
        let store = MemoryCredentialStore()
        let credentials = UnlockedWorkCredentials(preferences: preferences(), store: store)
        try await credentials.setEnabled(true)
        await store.setFailures(save: true, load: true)
        let candidate = try await credentials.credential { Data("synthetic\n".utf8) }
        XCTAssertTrue(credentials.message?.contains("synthetic read failure") == true)
        await credentials.authenticated(candidate)
        XCTAssertTrue(credentials.message?.contains("synthetic save failure") == true)
    }
}
