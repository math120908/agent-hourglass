import Foundation

public enum ProviderKind: String, Codable, Sendable { case claude, copilot, codex, google, grok, elevenlabs }

extension ProviderKind {
    /// Kinds whose meters are server-sized `.window` rows (Codex-style). New kinds default to true.
    public var usesWindowMeters: Bool { self != .claude && self != .copilot }

    /// Kinds that shipped builds (≤ v1.0.20) can decode. Frozen: never add a kind here.
    public var storesInMainRegistry: Bool { self == .claude || self == .copilot || self == .codex }

    /// The provider's own usage page, opened from the account card. `nil` hides the link.
    public var usagePageURL: URL? {
        switch self {
        case .claude: URL(string: "https://claude.ai/#settings/usage")
        case .codex: URL(string: "https://chatgpt.com/settings/usage?tab=overview")
        case .google: URL(string: "https://gemini.google.com/usage")
        case .copilot: URL(string: "https://github.com/settings/billing")
        case .grok: URL(string: "https://grok.com")
        case .elevenlabs: URL(string: "https://elevenlabs.io/app/subscription")
        }
    }
}
