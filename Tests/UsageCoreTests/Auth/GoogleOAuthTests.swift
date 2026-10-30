import Foundation
import Testing
@testable import UsageCore

// Provenance: token/userinfo field lists from R9 §1 (Antigravity OAuth client, no refresh rotation).
struct GoogleOAuthTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let client = GoogleOAuthClient(secret: Secret("test-secret"))
    static let redirect = "http://127.0.0.1:50123/callback"
    static let pkce = PKCE(verifier: Secret("VERIFIER-SENTINEL"), challenge: "CHALLENGE", state: "STATE-1")

    static func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static let idToken = "\(b64url(#"{"alg":"RS256"}"#)).\(b64url(#"{"sub":"sub-1","email":"pat@example.com"}"#)).sig"
    static let scope = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email"
    static func tokens(idToken: String? = idToken, refresh: Bool = true) -> (Int, String, [String: String]) {
        var fields = [#""access_token":"ACCESS-SENTINEL""#, #""expires_in":3599"#, "\"scope\":\"\(scope)\"", #""token_type":"Bearer""#]
        if refresh { fields.append(#""refresh_token":"REFRESH-SENTINEL""#) }
        if let idToken { fields.append("\"id_token\":\"\(idToken)\"") }
        return (200, "{\(fields.joined(separator: ","))}", [:])
    }
    static let invalidClient = (401, #"{"error":"invalid_client"}"#, [String: String]())
    static let invalidGrant = (400, #"{"error":"invalid_grant"}"#, [String: String]())

    func oauth(_ t: ScriptedTransport) -> GoogleOAuth {
        GoogleOAuth(http: HTTPClient(transport: t), now: { Self.t0 })
    }

    static let previous = Credential(
        kind: .google,
        access: Secret("OLD-ACCESS"),
        refresh: Secret("REFRESH-SENTINEL"),
        expiresAt: t0,
        refreshExpiresAt: nil,
        scopes: [],
        remoteAccountID: "sub-1",
        accountEmail: "pat@example.com"
    )

    @Test func authorizeURLParams() throws {
        let url = GoogleOAuth(http: HTTPClient(transport: ScriptedTransport([])))
            .authorizeURL(pkce: Self.pkce, redirectURI: Self.redirect, clientID: GoogleOAuth.antigravityClientID)
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.scheme == "https")
        #expect(c.host == "accounts.google.com")
        #expect(c.path == "/o/oauth2/v2/auth")
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(q["client_id"] == "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com")
        #expect(q["redirect_uri"] == Self.redirect)
        #expect(q["response_type"] == "code")
        #expect(q["scope"] == Self.scope)
        #expect(q["code_challenge"] == "CHALLENGE")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["state"] == "STATE-1")
        #expect(q["access_type"] == "offline")
        #expect(q["prompt"] == "select_account consent")
    }

    @Test func exchangeBuildsCredential() async throws {
        let t = ScriptedTransport([Self.tokens()])
        let c = try await oauth(t).exchange(code: "CODE+1", pkce: Self.pkce, redirectURI: Self.redirect, client: Self.client)
        try #require(t.requests.count == 1)
        let r = t.requests[0]
        #expect(r.httpMethod == "POST")
        #expect(r.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        let form = t.bodyForm(0)
        #expect(form["client_secret"] == "test-secret")
        #expect(form["client_id"] == GoogleOAuth.antigravityClientID)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "CODE+1")
        #expect(form["code_verifier"] == "VERIFIER-SENTINEL")
        #expect(form["redirect_uri"] == Self.redirect)
        #expect(c.kind == .google)
        #expect(c.access == Secret("ACCESS-SENTINEL"))
        #expect(c.refresh == Secret("REFRESH-SENTINEL"))
        #expect(c.expiresAt == Self.t0.addingTimeInterval(3599))
        #expect(c.scopes == ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email"])
        #expect(c.remoteAccountID == "sub-1")
        #expect(c.accountEmail == "pat@example.com")
    }

    @Test func exchangeWithoutIDTokenUsesUserinfo() async throws {
        let t = ScriptedTransport([Self.tokens(idToken: nil), (200, #"{"sub":"sub-2","email":"lee@example.com"}"#, [:])])
        let c = try await oauth(t).exchange(code: "CODE", pkce: Self.pkce, redirectURI: Self.redirect, client: Self.client)
        try #require(t.requests.count == 2)
        let r = t.requests[1]
        #expect(r.httpMethod == "GET")
        #expect(r.url?.absoluteString == "https://openidconnect.googleapis.com/v1/userinfo")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer ACCESS-SENTINEL")
        #expect(c.remoteAccountID == "sub-2")
        #expect(c.accountEmail == "lee@example.com")
    }

    @Test func userinfoWithoutSubIsSchema() async {
        let t = ScriptedTransport([Self.tokens(idToken: nil), (200, #"{"email":"lee@example.com"}"#, [:])])
        await #expect(throws: ProviderError.schema(keys: ["sub"])) {
            try await oauth(t).exchange(code: "CODE", pkce: Self.pkce, redirectURI: Self.redirect, client: Self.client)
        }
    }

    @Test func exchangeWithoutAccessTokenIsSchema() async {
        let t = ScriptedTransport([(200, #"{"expires_in":3599}"#, [:])])
        await #expect(throws: ProviderError.schema(keys: ["expires_in"])) {
            try await oauth(t).exchange(code: "CODE", pkce: Self.pkce, redirectURI: Self.redirect, client: Self.client)
        }
    }

    @Test func exchange400IsInvalidGrant() async {
        let t = ScriptedTransport([Self.invalidGrant])
        await #expect(throws: ProviderError.invalidGrant) {
            try await oauth(t).exchange(code: "CODE", pkce: Self.pkce, redirectURI: Self.redirect, client: Self.client)
        }
    }

    @Test func exchange401IsClientRejected() async {
        let t = ScriptedTransport([Self.invalidClient])
        await #expect(throws: GoogleOAuthError.clientRejected) {
            try await oauth(t).exchange(code: "CODE", pkce: Self.pkce, redirectURI: Self.redirect, client: Self.client)
        }
    }

    @Test func refreshKeepsRefreshTokenAndIdentity() async throws {
        let t = ScriptedTransport([Self.tokens(idToken: nil, refresh: false)])
        let c = try await oauth(t).refresh(Self.previous, client: Self.client)
        try #require(t.requests.count == 1)
        #expect(t.requests[0].url?.absoluteString == "https://oauth2.googleapis.com/token")
        let form = t.bodyForm(0)
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["refresh_token"] == "REFRESH-SENTINEL")
        #expect(form["client_secret"] == "test-secret")
        #expect(form["client_id"] == GoogleOAuth.antigravityClientID)
        #expect(c.access == Secret("ACCESS-SENTINEL"))
        #expect(c.refresh == Secret("REFRESH-SENTINEL"))
        #expect(c.remoteAccountID == "sub-1")
        #expect(c.accountEmail == "pat@example.com")
        #expect(c.expiresAt == Self.t0.addingTimeInterval(3599))
        #expect(c.kind == .google)
    }

    @Test func refresh400IsInvalidGrant() async {
        let t = ScriptedTransport([Self.invalidGrant])
        await #expect(throws: ProviderError.invalidGrant) { try await oauth(t).refresh(Self.previous, client: Self.client) }
    }

    @Test func refresh401IsClientRejected() async {
        let t = ScriptedTransport([Self.invalidClient])
        await #expect(throws: GoogleOAuthError.clientRejected) { try await oauth(t).refresh(Self.previous, client: Self.client) }
    }

    @Test func refreshWithoutRefreshTokenIsInvalidGrantWithoutNetwork() async {
        var c = Self.previous
        c.refresh = nil
        let t = ScriptedTransport([])
        await #expect(throws: ProviderError.invalidGrant) { try await oauth(t).refresh(c, client: Self.client) }
        #expect(t.requests.isEmpty)
    }

    @Test func probe401False() async throws {
        #expect(try await oauth(ScriptedTransport([Self.invalidClient])).probe(Self.client) == false)
    }

    @Test func probe400True() async throws {
        #expect(try await oauth(ScriptedTransport([Self.invalidGrant])).probe(Self.client) == true)
    }

    @Test func probe500Rethrows() async {
        let t = ScriptedTransport([(500, "{}", [:])])
        await #expect(throws: ProviderError.http(status: 500, host: "oauth2.googleapis.com", retryAfter: nil)) {
            try await oauth(t).probe(Self.client)
        }
    }

    @Test func probeTargetsTokenEndpoint() async throws {
        let t = ScriptedTransport([Self.invalidGrant])
        _ = try await oauth(t).probe(Self.client)
        try #require(t.requests.count == 1)
        let r = t.requests[0]
        #expect(r.httpMethod == "POST")
        #expect(r.url?.scheme == "https")
        #expect(r.url?.host() == "oauth2.googleapis.com")
        #expect(r.url?.path() == "/token")
        let form = t.bodyForm(0)
        #expect(form["code"] == "agent-hourglass-probe")
        #expect(form["redirect_uri"] == "http://127.0.0.1/callback")
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["client_secret"] == "test-secret")
        #expect(form["code_verifier"] == nil)
    }

    @Test func tokenHostsArePinned() {
        #expect(HTTPClient.noRedirectHosts.contains("oauth2.googleapis.com"))
        #expect(HTTPClient.authHosts.contains("openidconnect.googleapis.com"))
    }
}
