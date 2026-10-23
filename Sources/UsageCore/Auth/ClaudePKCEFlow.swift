import Foundation

/// Claude OAuth authorization-code + PKCE flow. The redirect URI is supplied by the caller
/// (loopback on macOS, `manualRedirectURI` for paste-the-code flows).
public struct ClaudePKCEFlow: Sendable {
    public static let manualRedirectURI = "https://platform.claude.com/oauth/code/callback"

    /// Exchanges `(code, pkce, redirectURI)` for a credential and the remote account id.
    public typealias Exchange = @Sendable (String, PKCE, String) async throws -> (Credential, String)

    private let exchanger: Exchange

    public init(exchange: Exchange? = nil) {
        self.exchanger = exchange ?? { code, pkce, redirect in
            try await ClaudePKCEFlow.liveExchange(code: code, pkce: pkce, redirect: redirect, http: HTTPClient())
        }
    }

    /// The code may arrive as `code#state`; keep only the part before `#`.
    package static func stripFragment(_ code: String) -> String {
        String(code.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    public func authorizeURL(pkce: PKCE, redirectURI: String, loginHint: String?) -> URL {
        var c = URLComponents(url: ClaudeOAuth.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: ClaudeOAuth.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: ClaudeOAuth.scope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: pkce.state),
        ] + (loginHint.map { [.init(name: "login_hint", value: $0)] } ?? [])
        return c.url!
    }

    /// Exchanges an already-clean authorization code (no `#state` suffix) for a credential.
    public func exchange(code: String, pkce: PKCE, redirectURI: String) async throws -> (Credential, String) {
        try await exchanger(code, pkce, redirectURI)
    }

    static func liveExchange(code: String, pkce: PKCE, redirect: String, http: HTTPClient) async throws -> (Credential, String) {
        var req = URLRequest(url: ClaudeOAuth.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect,
            "client_id": ClaudeOAuth.clientID,
            "code_verifier": pkce.verifier.reveal(),
            "state": pkce.state,
        ])
        // HTTPClient drops the body on non-2xx, so the expired / used code (OAuth `invalid_grant`)
        // is recognized by its status, the same way as on refresh.
        let data: Data
        let resp: HTTPURLResponse
        do {
            (data, resp) = try await http.send(req, bearer: nil)
        } catch ProviderError.http(status: 400, _, _) {
            throw ProviderError.invalidGrant
        }
        guard resp.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String
        else { throw ProviderError.http(status: resp.statusCode, host: ClaudeOAuth.tokenURL.host() ?? "", retryAfter: nil) }
        let now = Date()
        let cred = Credential(
            kind: .claude,
            access: Secret(access),
            refresh: (j["refresh_token"] as? String).map(Secret.init),
            expiresAt: (j["expires_in"] as? Double).map { now.addingTimeInterval($0) },
            refreshExpiresAt: (j["refresh_token_expires_in"] as? Double).map { now.addingTimeInterval($0) },
            scopes: ((j["scope"] as? String) ?? ClaudeOAuth.scope).split(separator: " ").map(String.init)
        )
        guard let id = (j["account"] as? [String: Any])?["uuid"] as? String else {
            throw ProviderError.schema(keys: j.keys.sorted())
        }
        return (cred, id)
    }
}
