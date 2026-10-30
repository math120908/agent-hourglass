public enum ProviderKind: String, Codable, Sendable { case claude, copilot, codex }

extension ProviderKind {
    /// Kinds whose meters are server-sized `.window` rows (Codex-style). New kinds default to true.
    public var usesWindowMeters: Bool { self != .claude && self != .copilot }

    /// Kinds that shipped builds (≤ v1.0.20) can decode. Frozen: never add a kind here.
    public var storesInMainRegistry: Bool { self == .claude || self == .copilot || self == .codex }
}
