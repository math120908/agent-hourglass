public enum ProviderKind: String, Codable, Sendable { case claude, copilot, codex }

extension ProviderKind {
    /// Kinds whose meters are server-sized `.window` rows (Codex-style). New kinds default to true.
    public var usesWindowMeters: Bool { self != .claude && self != .copilot }
}
