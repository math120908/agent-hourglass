import Foundation
import os
import Security

/// The login Claude Code keeps in its own Keychain item: only the fields we use.
/// There is deliberately no refresh-token field, so it never enters a Swift value.
public struct ClaudeCodeLogin: Sendable, Equatable {
    public let access: Secret
    public let expiresAt: Date?
    public let subscriptionType: String?

    public init(access: Secret, expiresAt: Date?, subscriptionType: String?) {
        self.access = access
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }

    /// Claude Code itself treats a token as expired 5 minutes before `expiresAt` (R6 §3).
    public static let expiryMargin: TimeInterval = 300

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(Self.expiryMargin) >= expiresAt
    }

    private struct Root: Decodable { let claudeAiOauth: OAuth? }
    private struct OAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let subscriptionType: String?
    }

    static func parse(_ data: Data) throws -> ClaudeCodeLogin {
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let o = root.claudeAiOauth, let token = o.accessToken, !token.isEmpty else {
            throw ClaudeCodeKeychainError.malformed
        }
        return ClaudeCodeLogin(
            access: Secret(token),
            expiresAt: o.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: o.subscriptionType
        )
    }
}

public enum ClaudeCodeKeychainError: Error, Sendable, Equatable {
    case notFound
    case userCanceled
    case interactionNotAllowed
    case malformed
    case other(status: Int32)
}

/// Anything that can hand out the current Claude Code login. Read-only by construction.
public protocol ClaudeCodeLoginReading: Sendable {
    func read() throws -> ClaudeCodeLogin
}

#if os(macOS)
/// Read-only view of Claude Code's Keychain item (default config dir only).
/// Only `SecItemCopyMatching`. Never adds, updates, deletes, or changes the item's access.
/// No caching: every call re-reads so a token refreshed by Claude Code is picked up.
public struct ClaudeCodeKeychainReader: ClaudeCodeLoginReading {
    public static let service = "Claude Code-credentials"
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "ClaudeCodeKeychain")

    public let account: String

    public init(account: String = ClaudeCodeKeychainReader.defaultAccount()) { self.account = account }

    /// Same rule as Claude Code: `$USER` if it matches `^[a-zA-Z0-9._-]+$`, else `claude-code-user`.
    public static func defaultAccount(_ user: String = NSUserName()) -> String {
        let ok = !user.isEmpty && user.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        return ok ? user : "claude-code-user"
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }

    public func read() throws -> ClaudeCodeLogin {
        let modified = modificationDate()
        var q = baseQuery
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        let mod = modified.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        let outcome: String
        defer { Self.log.notice("claude-code read outcome=\(outcome, privacy: .public) itemModified=\(mod, privacy: .public)") }
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { outcome = "malformed"; throw ClaudeCodeKeychainError.malformed }
            do {
                let login = try ClaudeCodeLogin.parse(data)
                outcome = "ok"
                return login
            } catch {
                outcome = "malformed"
                throw error
            }
        case errSecItemNotFound: outcome = "notFound"; throw ClaudeCodeKeychainError.notFound
        case errSecUserCanceled, errSecAuthFailed: outcome = "userCanceled(\(status))"; throw ClaudeCodeKeychainError.userCanceled
        case errSecInteractionNotAllowed: outcome = "interactionNotAllowed"; throw ClaudeCodeKeychainError.interactionNotAllowed
        default: outcome = "other(\(status))"; throw ClaudeCodeKeychainError.other(status: status)
        }
    }

    /// Attributes only (no secret, no prompt): the item's modification date, to see whether Claude Code rewrote it.
    private func modificationDate() -> Date? {
        var q = baseQuery
        q[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return (out as? [String: Any])?[kSecAttrModificationDate as String] as? Date
    }
}
#endif
