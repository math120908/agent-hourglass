import Foundation

/// Parses the Claude manual-redirect callback, captured as a URL from a web view or pasted as
/// `code#state`. Nothing here logs the code, the state or any query string.
public enum ClaudeManualCallback {
    static let maxPastedBytes = 4096
    private static let expected = URLComponents(string: ClaudePKCEFlow.manualRedirectURI)!

    /// Accepts only `https://platform.claude.com/oauth/code/callback` with exactly one non-empty
    /// `code` and exactly one non-empty `state`. User, password, port or duplicate items yield nil.
    public static func parse(url: URL) -> (code: String, state: String)? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == expected.scheme,
              c.host?.lowercased() == expected.host,
              c.path == expected.path,
              c.user == nil, c.password == nil, c.port == nil,
              let items = c.queryItems
        else { return nil }
        let codes = items.filter { $0.name == "code" }
        let states = items.filter { $0.name == "state" }
        guard codes.count == 1, states.count == 1,
              let code = codes[0].value, !code.isEmpty,
              let state = states[0].value, !state.isEmpty
        else { return nil }
        return (code, state)
    }

    /// Trims whitespace, accepts a full callback URL, otherwise splits `code#state` on the first `#`.
    public static func parse(pasted: String) -> (code: String, state: String)? {
        guard pasted.utf8.count <= maxPastedBytes else { return nil }
        let s = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: s), u.scheme != nil { return parse(url: u) }
        let parts = s.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let code = String(parts[0]), state = String(parts[1])
        guard !code.isEmpty, !state.isEmpty,
              !(code + state).contains(where: { $0.isWhitespace || $0.isNewline })
        else { return nil }
        return (code, state)
    }

    /// Compares a received state with the expected one. False if either is empty or the lengths
    /// differ; otherwise a constant-time comparison. The caller (P4) must use this, never `==`,
    /// and must discard the expected state after one comparison, whether it matched or not.
    public static func stateMatches(_ received: String, expected: String) -> Bool {
        guard !received.isEmpty, !expected.isEmpty, received.utf8.count == expected.utf8.count else { return false }
        return constantTimeEqual(received, expected)
    }
}
