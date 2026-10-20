import Foundation

/// OAuth constants verified by the S1 spike.
public enum ClaudeOAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"
    public static let scope = "user:profile"
}
