// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Combine
import Foundation
import Security
import WakeMacCore

protocol UnlockedWorkCredentialStore: Sendable {
    func load() async throws -> Data?
    func save(_ password: Data) async throws
    func delete() async throws
}

struct UnlockedWorkCredential {
    enum Source { case remembered, interactive }
    var password: Data
    let source: Source
    var preferenceRevision: Int? = nil
}

/// The caller authenticates with macOS and verifies the resulting policy before
/// calling authenticated. Service/lease failures must not invalidate a password.
@MainActor final class UnlockedWorkCredentials: ObservableObject {
    static let preferenceKey = "orexin.work.rememberAccountPassword"
    @Published private(set) var enabled: Bool
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let preferences: UserDefaults
    private let store: any UnlockedWorkCredentialStore
    private var revision = 0

    init(preferences: UserDefaults, store: any UnlockedWorkCredentialStore = KeychainUnlockedWorkCredentialStore()) {
        self.preferences = preferences; self.store = store
        enabled = preferences.bool(forKey: Self.preferenceKey)
    }

    func setEnabled(_ value: Bool) async throws {
        guard !busy else { throw ModeError("账户密码设置正在更新，请稍后重试。") }
        busy = true; defer { busy = false }
        revision += 1
        if !value {
            do { try await store.delete() }
            catch { message = error.localizedDescription; throw error }
        }
        enabled = value
        preferences.set(value, forKey: Self.preferenceKey)
        message = value ? "下次成功授权后，将账户密码保存在本机钥匙串。" : "已关闭自动授权，并删除本机保存的账户密码。"
    }

    func credential(requestPassword: () throws -> Data) async throws -> UnlockedWorkCredential {
        if enabled, preferences.bool(forKey: Self.preferenceKey) {
            let currentRevision = revision
            do {
                if let password = try await store.load(), enabled, preferences.bool(forKey: Self.preferenceKey), currentRevision == revision {
                    return .init(password: password, source: .remembered, preferenceRevision: currentRevision)
                }
            } catch {
                message = LF("无法读取本机钥匙串：%@ 请手动授权。", error.localizedDescription)
            }
        }
        return try interactiveCredential(requestPassword: requestPassword)
    }

    func interactiveCredential(requestPassword: () throws -> Data) throws -> UnlockedWorkCredential {
        .init(password: try requestPassword(), source: .interactive, preferenceRevision: revision)
    }

    /// Saving is optional: a Keychain failure does not undo verified authorization.
    func authenticated(_ credential: UnlockedWorkCredential) async {
        guard enabled, preferences.bool(forKey: Self.preferenceKey), credential.source == .interactive,
              credential.preferenceRevision == revision else { return }
        let currentRevision = revision
        do {
            try await store.save(credential.password)
            // A settings change can interleave while the store suspends.
            if !enabled || !preferences.bool(forKey: Self.preferenceKey) || currentRevision != revision {
                try await store.delete()
                return
            }
            message = "账户密码已保存在本机钥匙串，后续工作将自动授权。"
        } catch { message = LF("本次授权已完成，但密码未能保存：%@", error.localizedDescription) }
    }

    /// Use only for a confirmed account-authentication rejection. The caller may
    /// then make one interactive attempt; transport failures leave the item intact.
    func invalidateRememberedCredential() async throws {
        do {
            try await store.delete()
            message = "保存的账户密码未通过认证，已删除，请重新输入。"
        } catch { message = error.localizedDescription; throw error }
    }
}

/// The local login Keychain uses its default ACL for the current signed app.
/// Synchronization is explicitly disabled; no data-protection entitlement is needed.
actor KeychainUnlockedWorkCredentialStore: UnlockedWorkCredentialStore {
    private let disposableService = "com.orxooo.Orexin.credential-test." + UUID().uuidString
    private let disposableKeychain: SecKeychain?
    init() { disposableKeychain = nil }
    /// Used only by tests to exercise Security APIs against a disposable keychain.
    init(testKeychain: SecKeychain) { disposableKeychain = testKeychain }

    private var query: [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: disposableKeychain == nil ? "com.orxooo.Orexin.unlocked-work" : disposableService,
         kSecAttrAccount as String: NSUserName(),
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        if let disposableKeychain { result[kSecMatchSearchList as String] = [disposableKeychain] }
        return result
    }

    func load() throws -> Data? {
        try requireSignedApplication()
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status, operation: "读取")
        guard let data = result as? Data else { throw ModeError("本机钥匙串中的账户密码格式无效。") }
        return data
    }

    func save(_ password: Data) throws {
        try requireSignedApplication()
        var request = query
        request[kSecValueData as String] = password
        if let disposableKeychain {
            request.removeValue(forKey: kSecMatchSearchList as String)
            request[kSecUseKeychain as String] = disposableKeychain
        }
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try check(SecItemUpdate(query as CFDictionary, [kSecValueData as String: password] as CFDictionary), operation: "保存")
        } else { try check(status, operation: "保存") }
    }

    func delete() throws {
        try requireSignedApplication()
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status, operation: "删除") }
    }

    private func requireSignedApplication() throws {
        if disposableKeychain != nil { return }
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard Bundle.main.bundleIdentifier == "com.orxooo.Orexin",
              SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty else {
            throw ModeError("请使用已签名的 Orexin 应用保存或读取账户密码。")
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == errSecSuccess else {
            // Only the operation and OS status are surfaced, never secret data.
            throw ModeError(LF("本机钥匙串%@失败（%d）。", L(operation), status))
        }
    }
}
