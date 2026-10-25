import Foundation

/// The user name Claude Code reports in `~/.claude.json` (`oauthAccount`). Reads only name/email
/// fields; tokens are never read or logged.
public enum ClaudeCodeProfile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// displayName, then fullName, then emailAddress; nil when the file or every field is missing.
    public static func userName(at url: URL = defaultURL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any]
        else { return nil }
        return ["displayName", "fullName", "emailAddress"].lazy
            .compactMap { (account[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
