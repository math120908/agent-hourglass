import Foundation
import Testing
@testable import UsageCore

// Provenance: loopback PKCE redirect shape from R9 §1 (Antigravity OAuth client).
struct GoogleSignInTests {
    actor UnavailableClientSource: GoogleOAuthClientSource {
        func client() async throws -> GoogleOAuthClient { throw GoogleOAuthError.clientUnavailable }
        func invalidate() async {}
    }

    final class OpenRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var opened: [URL] { lock.withLock { urls } }
        func record(_ url: URL) { lock.withLock { urls.append(url) } }
    }

    func signIn(_ t: ScriptedTransport, client: any GoogleOAuthClientSource = StubGoogleClientSource()) -> GoogleSignIn {
        GoogleSignIn(oauth: GoogleOAuth(http: HTTPClient(transport: t), now: { GoogleOAuthTests.t0 }), client: client)
    }

    /// Plays the browser: reads `state` and `redirect_uri` from the authorize URL and hits the redirect.
    static func callback(_ url: URL, code: String = "abc", state override: String? = nil) async {
        let q = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a }
        )
        guard var c = URLComponents(string: q["redirect_uri"] ?? "") else { return }
        c.queryItems = [URLQueryItem(name: "code", value: code), URLQueryItem(name: "state", value: override ?? q["state"])]
        _ = try? await URLSession.shared.data(from: c.url!)
    }

    @Test func redirectURIIsLoopbackCallback() {
        #expect(GoogleSignIn.redirectURI(port: 50123) == "http://127.0.0.1:50123/callback")
    }

    @Test func clientUnavailableBeforeBinding() async throws {
        let opens = OpenRecorder()
        await #expect(throws: GoogleOAuthError.clientUnavailable) {
            _ = try await signIn(ScriptedTransport([]), client: UnavailableClientSource())
                .run(open: { opens.record($0) }, timeout: .seconds(5))
        }
        #expect(opens.opened.isEmpty)
    }

    @Test func endToEndCallback() async throws {
        let t = ScriptedTransport([GoogleOAuthTests.tokens()])
        let opens = OpenRecorder()
        let c = try await signIn(t).run(open: { opens.record($0); await Self.callback($0) }, timeout: .seconds(10))
        #expect(c.kind == .google)
        #expect(c.remoteAccountID == "sub-1")
        try #require(opens.opened.count == 1)
        #expect(opens.opened[0].host == "accounts.google.com")
        try #require(t.requests.count == 1)
        let form = t.bodyForm(0)
        #expect(form["code"] == "abc")
        let redirect = try #require(form["redirect_uri"].flatMap(URL.init(string:)))
        #expect(redirect.host == "127.0.0.1")
        #expect(redirect.path == "/callback")
    }

    @Test func stateMismatchThrows() async throws {
        let t = ScriptedTransport([])
        await #expect(throws: AuthError.stateMismatch) {
            _ = try await signIn(t).run(open: { await Self.callback($0, state: "wrong-state") }, timeout: .seconds(10))
        }
        #expect(t.requests.isEmpty)
    }

    @Test func clientRejectedInvalidatesCachedClient() async throws {
        let source = StubGoogleClientSource()
        await #expect(throws: GoogleOAuthError.clientUnavailable) {
            _ = try await signIn(ScriptedTransport([GoogleOAuthTests.invalidClient]), client: source)
                .run(open: { await Self.callback($0) }, timeout: .seconds(10))
        }
        #expect(await source.invalidations == 1)
    }
}
