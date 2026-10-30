import Foundation

public enum AccountStatus: Codable, Sendable, Equatable {
    case fresh
    case stale
    case rateLimited(retryAt: Date)
    case offline
    case needsLogin
    case ghMissing
    case ghLoginRemoved
    case schemaError
    case noData
    /// No usable ChatGPT login in ~/.codex/auth.json (missing, API-key mode, unsafe permissions, malformed).
    case codexNotSignedIn
    /// Claude Code (local): no Claude Code Keychain item.
    case claudeCodeNotSignedIn
    /// Claude Code (local): token within 5 min of expiry, or a 401. Claude Code refreshes it when used.
    case claudeCodeExpired
    /// Claude Code (local): Keychain access denied or unavailable. No further reads until re-added or relaunched.
    case claudeCodeDenied
    /// Signed in, but the server returned no trustworthy quota (placeholder, 403, unconfirmed all-100%).
    case quotaUnavailable
}
