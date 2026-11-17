// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

enum UnlockedWorkAuthenticationError: LocalizedError {
    case rejected, interrupted
    var errorDescription: String? {
        switch self {
        case .rejected: "macOS 未接受授权；请确认账户密码，或检查设备管理策略。"
        case .interrupted: "账户认证未完成，请重新授权。"
        }
    }
}

@MainActor enum UnlockedWorkAuthentication {
    static func authorize(credentials: UnlockedWorkCredentials,
                          requestPassword: @MainActor () throws -> Data,
                          renew: () async throws -> Void,
                          apply: (Data) async throws -> Void,
                          verify: () async throws -> Void) async throws {
        var credential = try await credentials.credential(requestPassword: requestPassword)
        defer { credential.password.resetBytes(in: 0..<credential.password.count) }
        try await renew()
        do { try await apply(credential.password) }
        catch UnlockedWorkAuthenticationError.rejected where credential.source == .remembered {
            try await credentials.invalidateRememberedCredential()
            credential.password.resetBytes(in: 0..<credential.password.count)
            credential = try credentials.interactiveCredential(requestPassword: requestPassword)
            try await renew()
            try await apply(credential.password)
        }
        try await verify()
        await credentials.authenticated(credential)
    }
}
