/// Stable account key, `"<kind>:<remoteID>"`.
public struct AccountID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) { self.rawValue = rawValue }

    public init(kind: ProviderKind, remoteID: String) { rawValue = "\(kind.rawValue):\(remoteID)" }

    /// The single read-only "Claude Code (local)" account (default Claude Code config dir).
    public static let claudeCodeLocal = AccountID(kind: .claude, remoteID: "claude-code-local")
    public var isClaudeCodeLocal: Bool { self == .claudeCodeLocal }

    public var kind: ProviderKind? {
        guard let prefix = rawValue.split(separator: ":", maxSplits: 1).first else { return nil }
        return ProviderKind(rawValue: String(prefix))
    }
}
