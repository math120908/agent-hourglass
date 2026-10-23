import Foundation

public enum GhError: Error, Equatable, Sendable {
    case missing
    case untrusted
    case loginRemoved
    case timeout
}

/// Supplies GitHub tokens for Copilot accounts. The Mac app borrows them from `gh`;
/// other platforms can provide their own source.
public protocol CopilotTokenSource: Sendable {
    func token(for login: String) async throws -> Secret
    func invalidate(_ login: String)
}
