import Foundation

/// Google loopback PKCE sign-in: browser to Google, redirect to `127.0.0.1`, code exchanged for tokens.
public struct GoogleSignIn: Sendable {
    private let oauth: GoogleOAuth
    private let client: any GoogleOAuthClientSource

    public init(oauth: GoogleOAuth, client: any GoogleOAuthClientSource) {
        self.oauth = oauth
        self.client = client
    }

    public static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)/callback" }

    /// The client is resolved first, so a missing secret throws before a port is bound or a browser opened.
    public func run(open: @escaping @Sendable (URL) async -> Void, timeout: Duration = .seconds(300)) async throws -> Credential {
        let c = try await client.client()
        let pkce = PKCE.make()
        let listener = try await LoopbackListener.bind()
        let redirect = Self.redirectURI(port: listener.port)
        let code: String
        do {
            await open(oauth.authorizeURL(pkce: pkce, redirectURI: redirect, clientID: c.clientID))
            code = try await listener.awaitCallback(expectedState: pkce.state, timeout: timeout)
        } catch {
            await listener.close()
            throw error
        }
        await listener.close()
        do {
            return try await oauth.exchange(code: code, pkce: pkce, redirectURI: redirect, client: c)
        } catch GoogleOAuthError.clientRejected {
            await client.invalidate()
            throw GoogleOAuthError.clientRejected
        }
    }
}
