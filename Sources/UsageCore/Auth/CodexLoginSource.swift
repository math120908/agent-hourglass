import Foundation

public enum CodexAuthError: Error, Equatable, Sendable {
    /// auth.json absent.
    case missing
    /// auth_mode is not `chatgpt` (e.g. API key): no usage windows to read.
    case notChatGPT
    /// Not owned by the current user, or group/world-writable.
    case untrusted
    /// Unreadable JSON or missing token fields.
    case malformed
}

/// A ChatGPT login usable for the Codex usage endpoint.
public struct CodexLogin: Sendable, Equatable {
    public let access: Secret
    public let accountID: String

    public init(access: Secret, accountID: String) {
        self.access = access
        self.accountID = accountID
    }
}

/// Where a Codex login comes from. `invalidate()` drops any cached login so the next `login()` re-reads.
public protocol CodexLoginSource: Sendable {
    func login() throws -> CodexLogin
    func invalidate()
}
