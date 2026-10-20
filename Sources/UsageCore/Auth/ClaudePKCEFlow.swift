import Foundation

/// Claude OAuth authorization-code + PKCE flow over a loopback redirect.
public struct ClaudePKCEFlow: Sendable {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeEndpoint = URL(string: "https://claude.com/cai/oauth/authorize")!
    public static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let scope = "user:profile"

    /// Exchanges `(code, pkce, redirectURI)` for a credential and the remote account id.
    public typealias Exchange = @Sendable (String, PKCE, String) async throws -> (Credential, String)

    let exchange: Exchange

    public init(exchange: Exchange? = nil) {
        self.exchange = exchange ?? { code, pkce, redirect in
            try await ClaudePKCEFlow.liveExchange(code: code, pkce: pkce, redirect: redirect, http: HTTPClient())
        }
    }

    static func redirectURI(port: UInt16) -> String { "http://localhost:\(port)/callback" }

    /// The code may arrive as `code#state`; keep only the part before `#`.
    static func stripFragment(_ code: String) -> String {
        String(code.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    public func authorizeURL(pkce: PKCE, port: UInt16, loginHint: String?) -> URL {
        var c = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI(port: port)),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: pkce.state),
        ] + (loginHint.map { [.init(name: "login_hint", value: $0)] } ?? [])
        return c.url!
    }

    public func run(
        loginHint: String?,
        open: (URL) -> Void,
        expectedRemoteID: String? = nil
    ) async throws -> (Credential, remoteAccountID: String) {
        let pkce = PKCE.make()
        let listener = try await LoopbackListener.bind()
        let code: String
        do {
            open(authorizeURL(pkce: pkce, port: listener.port, loginHint: loginHint))
            code = try await listener.awaitCallback(expectedState: pkce.state)
        } catch {
            await listener.close()
            throw error
        }
        let (cred, remoteID) = try await exchange(code, pkce, Self.redirectURI(port: listener.port))
        if let expectedRemoteID, expectedRemoteID != remoteID { throw AuthError.differentAccount }
        return (cred, remoteID)
    }

    static func liveExchange(code: String, pkce: PKCE, redirect: String, http: HTTPClient) async throws -> (Credential, String) {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect,
            "client_id": clientID,
            "code_verifier": pkce.verifier.reveal(),
            "state": pkce.state,
        ])
        let (data, resp) = try await http.send(req, bearer: nil)
        guard resp.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String
        else { throw ProviderError.http(status: resp.statusCode, host: tokenEndpoint.host() ?? "", retryAfter: nil) }
        let now = Date()
        let cred = Credential(
            kind: .claude,
            access: Secret(access),
            refresh: (j["refresh_token"] as? String).map(Secret.init),
            expiresAt: (j["expires_in"] as? Double).map { now.addingTimeInterval($0) },
            refreshExpiresAt: (j["refresh_token_expires_in"] as? Double).map { now.addingTimeInterval($0) },
            scopes: ((j["scope"] as? String) ?? scope).split(separator: " ").map(String.init)
        )
        guard let id = (j["account"] as? [String: Any])?["uuid"] as? String else {
            throw ProviderError.schema(keys: j.keys.sorted())
        }
        return (cred, id)
    }
}
