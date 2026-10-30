import Foundation

/// What a platform UI should offer for an account status. On iOS every provider re-auths in-app,
/// so every "not signed in" flavour maps to `.signIn`.
public enum StatusAction: Sendable, Equatable {
    case none, stale, signIn, rateLimited(retryAt: Date), formatChanged, offline

    public static func make(_ status: AccountStatus) -> StatusAction {
        switch status {
        case .fresh, .noData: return .none
        case .stale, .quotaUnavailable: return .stale
        case .needsLogin, .codexNotSignedIn, .ghMissing, .ghLoginRemoved,
             .claudeCodeNotSignedIn, .claudeCodeExpired, .claudeCodeDenied: return .signIn
        case .rateLimited(let at): return .rateLimited(retryAt: at)
        case .schemaError: return .formatChanged
        case .offline: return .offline
        }
    }
}
