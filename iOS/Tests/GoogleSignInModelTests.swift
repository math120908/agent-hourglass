import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

// Provenance: loopback PKCE redirect shape from R9 §1 (Antigravity OAuth client).

/// Answers with the queued bodies in order, then `fallback` forever; status 200.
private final class FixedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String]
    private let fallback: String
    init(_ queue: [String] = [], then fallback: String = "{}") {
        self.queue = queue
        self.fallback = fallback
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = lock.withLock { queue.isEmpty ? fallback : queue.removeFirst() }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func b64url(_ s: String) -> String {
    Data(s.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private let idToken = "\(b64url("{\"alg\":\"none\"}")).\(b64url(#"{"sub":"sub-1","email":"a@example.com"}"#)).sig"
private let tokens = #"{"access_token":"ACCESS-SENTINEL","refresh_token":"REFRESH-SENTINEL","expires_in":3599,"#
    + "\"id_token\":\"\(idToken)\"}"

private struct StubClientSource: GoogleOAuthClientSource {
    func client() async throws -> GoogleOAuthClient { GoogleOAuthClient(secret: Secret("test-secret")) }
    func invalidate() async {}
}

private struct UnavailableClientSource: GoogleOAuthClientSource {
    func client() async throws -> GoogleOAuthClient { throw GoogleOAuthError.clientUnavailable }
    func invalidate() async {}
}

private func query(_ url: URL) -> [String: String] {
    Dictionary(
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
        uniquingKeysWith: { a, _ in a }
    )
}

/// Plays the auth sheet. `redirects`: `start` hits the authorize URL's loopback redirect with its `state`,
/// as Google would. `holds`: `start` leaves the sheet open, as a user still on Google's page does.
/// Otherwise `start` ends the session at once, as a user closing the sheet does.
/// Like the real session, `cancel` also runs the completion.
private final class FakeSession: PasteAuthSession {
    let url: URL
    let redirects: Bool
    let holds: Bool
    let done: @Sendable () -> Void
    private(set) var started = 0
    private(set) var cancelled = 0

    init(url: URL, redirects: Bool, holds: Bool = false, done: @escaping @Sendable () -> Void) {
        self.url = url
        self.redirects = redirects
        self.holds = holds
        self.done = done
    }

    func start() -> Bool {
        started += 1
        if holds { return true }
        guard redirects else { done(); return true }
        let q = query(url)
        var c = URLComponents(string: q["redirect_uri"] ?? "")!
        c.queryItems = [URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: q["state"])]
        let target = c.url!
        Task.detached { _ = try? await URLSession.shared.data(from: target) }
        return true
    }

    func cancel() {
        cancelled += 1
        done()
    }
}

@MainActor private func waitUntil(_ cond: () -> Bool) async {
    for _ in 0..<500 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
}

/// True once nothing accepts connections on `port` (the listener closed its sockets).
private func refused(port: String, attempts: Int = 100) async -> Bool {
    let url = URL(string: "http://127.0.0.1:\(port)/probe")!
    for _ in 0..<attempts {
        do { _ = try await URLSession.shared.data(from: url) } catch { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

@MainActor
struct GoogleSignInModelTests {
    private func app() throws -> AppModel { try appAndEnv().0 }

    private func appAndEnv() throws -> (AppModel, UsageEnvironment) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let base = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let env = UsageEnvironment(
            directory: base.directory,
            registry: base.registry,
            store: base.store,
            shared: base.shared,
            http: HTTPClient(transport: FixedTransport()),
            googleConfigured: true
        )
        return (AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)), env)
    }

    private func signIn(_ client: any GoogleOAuthClientSource = StubClientSource()) -> GoogleSignIn {
        GoogleSignIn(oauth: GoogleOAuth(http: HTTPClient(transport: FixedTransport([tokens]))), client: client)
    }

    private func browser(redirects: Bool, holds: Bool = false) -> (PasteBrowser, () -> [FakeSession]) {
        var made: [FakeSession] = []
        let b = PasteBrowser { url, _, done in
            let s = FakeSession(url: url, redirects: redirects, holds: holds, done: done)
            made.append(s)
            return s
        }
        return (b, { made })
    }

    @Test func testRedirectCompletesAndDismissesBrowser() async throws {
        let (app, env) = try appAndEnv()
        await app.load()
        let (b, made) = browser(redirects: true)
        let m = GoogleSignInModel(app: app, signIn: signIn(), browser: b)
        m.start()
        #expect(m.state == .waiting)
        let id = AccountID(kind: .google, remoteID: "sub-1")
        await waitUntil { m.state != .waiting }
        #expect(m.state == .success(id))
        try #require(made().count == 1)
        #expect(made()[0].started == 1)
        #expect(made()[0].cancelled == 1)
        #expect(!b.isActive)
        #expect(await env.registry.accounts().map(\.id) == [id])
        try? await app.service.remove(id)
    }

    @Test func testClosingBrowserFirstCancels() async throws {
        let (app, env) = try appAndEnv()
        await app.load()
        let (b, made) = browser(redirects: false)
        let m = GoogleSignInModel(app: app, signIn: signIn(), browser: b)
        m.start()
        await waitUntil { m.state != .waiting }
        #expect(m.state == .failed("Sign-in was cancelled"))
        let session = try #require(made().first)
        let port = try #require(URLComponents(string: query(session.url)["redirect_uri"] ?? "")?.port)
        #expect(await refused(port: String(port)))
        #expect(await env.registry.accounts().isEmpty)
    }

    /// The add sheet went away mid-flow: the listener is released at once, not after the 300 s timeout.
    @Test func testCancelReleasesListener() async throws {
        let (app, env) = try appAndEnv()
        await app.load()
        let (b, made) = browser(redirects: false, holds: true)
        let m = GoogleSignInModel(app: app, signIn: signIn(), browser: b)
        m.start()
        await waitUntil { !made().isEmpty }
        let session = try #require(made().first)
        let port = try #require(URLComponents(string: query(session.url)["redirect_uri"] ?? "")?.port)
        #expect(!(await refused(port: String(port), attempts: 3)))
        m.cancel()
        #expect(session.cancelled == 1)
        #expect(await refused(port: String(port)))
        #expect(await env.registry.accounts().isEmpty)
    }

    @Test func testUnconfiguredClient() async throws {
        let app = try app()
        await app.load()
        let (b, made) = browser(redirects: true)
        let m = GoogleSignInModel(app: app, signIn: signIn(UnavailableClientSource()), browser: b)
        m.start()
        await waitUntil { m.state != .waiting }
        #expect(m.state == .failed("Google sign-in is not configured in this build"))
        #expect(made().isEmpty)
    }

    @Test func testClientRejectedUsesGoogleFailureText() async throws {
        let app = try app()
        await app.load()
        let (b, _) = browser(redirects: true)
        let rejecting = GoogleSignIn(oauth: GoogleOAuth(http: HTTPClient(transport: StatusTransport(401))), client: StubClientSource())
        let m = GoogleSignInModel(app: app, signIn: rejecting, browser: b)
        m.start()
        await waitUntil { m.state != .waiting }
        #expect(m.state == .failed("Google rejected the Antigravity client. Retry"))
        #expect(!b.isActive)
    }
}

/// Answers every request with `status` and an OAuth error body.
private struct StatusTransport: HTTPTransport {
    let status: Int
    init(_ status: Int) { self.status = status }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(#"{"error":"invalid_client"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
