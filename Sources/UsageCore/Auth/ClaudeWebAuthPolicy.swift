import Foundation

/// Navigation policy for the Claude sign-in web view. The callback is captured (and must be
/// cancelled by the caller so it never loads); allowlisted https hosts load; everything else is
/// blocked. Nothing here logs the URL, code or state.
public enum ClaudeWebAuthPolicy {
    public enum Decision: Equatable {
        case allow
        case capture(code: String, state: String)
        case block
    }

    /// Matched on a dot boundary: the host equals a suffix or ends with "." + suffix.
    /// `hcaptcha.com` is required by the authorize page (S4 spike: newassets.hcaptcha.com).
    public static let allowedHostSuffixes: [String] = [
        "claude.com", "claude.ai", "anthropic.com", "challenges.cloudflare.com", "hcaptcha.com",
    ]

    private static let callback = URLComponents(string: ClaudePKCEFlow.manualRedirectURI)!

    public static func decide(_ url: URL) -> Decision {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https",
              let host = c.host?.lowercased(), !host.isEmpty
        else { return .block }
        if host == callback.host, c.path == callback.path {
            guard let p = ClaudeManualCallback.parse(url: url) else { return .block }
            return .capture(code: p.code, state: p.state)
        }
        guard c.user == nil, c.password == nil else { return .block }
        let ok = allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
        return ok ? .allow : .block
    }
}
