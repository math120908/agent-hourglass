import Foundation
import os

/// The Google OAuth client the app signs in as. The secret is discovered at runtime, never committed.
public struct GoogleOAuthClient: Sendable, Equatable {
    public let clientID: String
    public let secret: Secret

    public init(clientID: String = GoogleOAuth.antigravityClientID, secret: Secret) {
        self.clientID = clientID
        self.secret = secret
    }
}

public protocol GoogleOAuthClientSource: Sendable {
    func client() async throws -> GoogleOAuthClient
    /// Drops a cached secret that Google rejected (token endpoint 401 `invalid_client`).
    func invalidate() async
}

public enum GoogleOAuthError: Error, Equatable, Sendable {
    case clientUnavailable, clientRejected
}

/// Google loopback PKCE sign-in as the Antigravity client: authorize URL, code exchange, refresh, probe.
public struct GoogleOAuth: Sendable {
    public static let antigravityClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    public static let authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    /// Every token POST goes here; no method takes a URL.
    public static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let userinfoURL = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
    public static let scope = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email"
    /// A bogus code: Google answers 400 invalid_grant for the right secret, 401 invalid_client for a wrong one.
    public static let probeCode = "agent-hourglass-probe"
    static let probeRedirectURI = "http://127.0.0.1/callback"

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "GoogleOAuth")

    private let http: HTTPClient
    private let now: @Sendable () -> Date

    public init(http: HTTPClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.now = now
    }

    public func authorizeURL(pkce: PKCE, redirectURI: String, clientID: String) -> URL {
        var c = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
        ]
        return c.url!
    }

    public func exchange(code: String, pkce: PKCE, redirectURI: String, client: GoogleOAuthClient) async throws -> Credential {
        let data = try await token([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", pkce.verifier.reveal()),
            ("redirect_uri", redirectURI),
        ], client: client, step: "exchange")
        var c = try credential(fromTokenResponse: data, previous: nil)
        if c.remoteAccountID == nil {
            (c.remoteAccountID, c.accountEmail) = try await userinfo(c.access)
        }
        return c
    }

    /// Google does not rotate refresh tokens (R9): the previous one and the identity are kept.
    public func refresh(_ c: Credential, client: GoogleOAuthClient) async throws -> Credential {
        guard let rt = c.refresh?.reveal(), !rt.isEmpty else {
            Self.log.error("refresh: invalidGrant (no refresh token)")
            throw ProviderError.invalidGrant
        }
        let data = try await token([("grant_type", "refresh_token"), ("refresh_token", rt)], client: client, step: "refresh")
        return try credential(fromTokenResponse: data, previous: c)
    }

    /// True when Google accepts `client` (400 invalid_grant for the bogus code), false on 401 invalid_client.
    /// [inferred] status split from R9; recorded as a morning check.
    public func probe(_ client: GoogleOAuthClient) async throws -> Bool {
        do {
            _ = try await token([
                ("grant_type", "authorization_code"),
                ("code", Self.probeCode),
                ("redirect_uri", Self.probeRedirectURI),
            ], client: client, step: "probe")
            return true
        } catch GoogleOAuthError.clientRejected {
            return false
        } catch ProviderError.invalidGrant {
            return true
        }
    }

    private func userinfo(_ access: Secret) async throws -> (String, String?) {
        var req = URLRequest(url: Self.userinfoURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        do {
            data = try await http.send(req, bearer: access).0
        } catch let error as ProviderError {
            Self.log.error("userinfo failed: \(error.description, privacy: .public)")
            throw error
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let sub = Self.nonEmpty(obj?["sub"]) else { throw ProviderError.schema(keys: ["sub"]) }
        return (sub, Self.nonEmpty(obj?["email"]))
    }

    /// Form POST to `tokenURL` with the client id and secret. 400 → invalidGrant, 401 → clientRejected.
    private func token(_ fields: [(String, String)], client: GoogleOAuthClient, step: StaticString) async throws -> Data {
        var c = URLComponents()
        c.queryItems = (fields + [("client_id", client.clientID), ("client_secret", client.secret.reveal())])
            .map { URLQueryItem(name: $0.0, value: $0.1) }
        let form = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Data(form.utf8)
        do {
            let data = try await http.send(req, bearer: nil).0
            Self.log.info("\(step, privacy: .public): HTTP 200")
            return data
        } catch ProviderError.unauthorized {
            Self.log.error("\(step, privacy: .public): HTTP 401 clientRejected")
            throw GoogleOAuthError.clientRejected
        } catch let ProviderError.http(status, _, _) where status == 400 {
            Self.log.info("\(step, privacy: .public): HTTP 400 invalidGrant")
            throw ProviderError.invalidGrant
        } catch let error as ProviderError {
            Self.log.error("\(step, privacy: .public) failed: \(error.description, privacy: .public)")
            throw error
        }
    }

    /// Identity comes from the id_token (no signature check: it arrived over TLS from Google) or,
    /// on refresh, from `previous`. A nil `remoteAccountID` means the caller asks userinfo.
    private func credential(fromTokenResponse data: Data, previous: Credential?) throws -> Credential {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.schema(keys: [])
        }
        guard let access = Self.nonEmpty(obj["access_token"]) else {
            throw ProviderError.schema(keys: obj.keys.sorted())
        }
        let claims = (obj["id_token"] as? String).flatMap(CodexDeviceAuth.jwtPayload)
        let sub = Self.nonEmpty(claims?["sub"])
        let refresh = Self.nonEmpty(obj["refresh_token"]).map(Secret.init) ?? previous?.refresh
        let scopes = (obj["scope"] as? String)?.split(separator: " ").map(String.init) ?? previous?.scopes ?? []
        return Credential(
            kind: .google,
            access: Secret(access),
            refresh: refresh,
            expiresAt: CodexDeviceAuth.number(obj["expires_in"]).map { now().addingTimeInterval($0) },
            refreshExpiresAt: nil,
            scopes: scopes,
            remoteAccountID: sub ?? previous?.remoteAccountID,
            accountEmail: sub != nil ? Self.nonEmpty(claims?["email"]) : previous?.accountEmail
        )
    }

    private static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        return s
    }
}
