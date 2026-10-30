import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

/// Provenance: file enumeration and the 28-char GOCSPX- length mirror CodexBar
/// `AntigravityOAuthCredentialsStore.swift` `candidateOAuthClientArtifactURLs` at `5f93dc3`;
/// the code-free probe split (401 wrong / 400 right) is R9 §1 + G9 `GoogleOAuth.probe`.
///
/// Secrets are built at runtime so no `GOCSPX-…` literal enters the repo (secret-scan rule).
struct AntigravityClientDiscoveryTests {
    /// A client-secret-shaped string, never a real secret.
    static func fakeSecret(_ fill: Character = "a") -> String {
        "GOCSPX-" + String(repeating: fill, count: 28)
    }

    static let clientID = GoogleOAuth.antigravityClientID

    /// Answers a token POST 401 (`invalid_client`) for every secret except the ones in `accept`,
    /// which get 400 (`invalid_grant`). Records each request.
    final class ProbeTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private let accept: Set<String>

        init(accept: Set<String> = []) { self.accept = accept }

        var requests: [URLRequest] { lock.withLock { recorded } }

        func secret(_ i: Int) -> String? {
            guard let body = requests[i].httpBody, let s = String(data: body, encoding: .utf8) else { return nil }
            var c = URLComponents()
            c.percentEncodedQuery = s
            return (c.queryItems ?? []).first { $0.name == "client_secret" }?.value
        }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let secret: String? = {
                guard let body = request.httpBody, let s = String(data: body, encoding: .utf8) else { return nil }
                var c = URLComponents()
                c.percentEncodedQuery = s
                return (c.queryItems ?? []).first { $0.name == "client_secret" }?.value
            }()
            let status = (secret.map(accept.contains) ?? false) ? 400 : 401
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            lock.withLock { recorded.append(request) }
            return (Data("{}".utf8), resp)
        }
    }

    // MARK: - Temp files

    /// A unique temp directory for one test; removed when the returned handle is released.
    final class TempDir: @unchecked Sendable {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("agd-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        @discardableResult
        func write(_ name: String, _ body: Data, mode: Int16 = 0o600) -> URL {
            let f = url.appendingPathComponent(name)
            try? body.write(to: f)
            try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: f.path)
            return f
        }
    }

    /// `files`-injected discovery over a probe transport; secrets in `accept` probe true.
    func discovery(files: [URL], accept: Set<String> = [], cache: any CredentialStoring = InMemoryCredentialStore()) -> (AntigravityClientDiscovery, ProbeTransport) {
        let t = ProbeTransport(accept: accept)
        let d = AntigravityClientDiscovery(oauth: GoogleOAuth(http: HTTPClient(transport: t)), cache: cache, files: files)
        return (d, t)
    }

    /// A binary blob that contains the Antigravity client id plus `secrets`.
    static func blob(_ secrets: [String]) -> Data {
        var s = "noise " + clientID + " noise "
        s += secrets.joined(separator: " gap ")
        return Data(s.utf8)
    }

    // MARK: - candidates()

    @Test func candidatesFoundInOrderDeduplicated() {
        let a = Self.fakeSecret("a"), b = Self.fakeSecret("b")
        let found = AntigravityClientDiscovery.candidates(in: Self.blob([a, b, a]))
        #expect(found == [a, b])
    }

    @Test func candidateFollowedByExtraBytes() {
        let a = Self.fakeSecret("a")
        let data = Data(("x " + a + "bcdef y").utf8)
        let found = AntigravityClientDiscovery.candidates(in: data)
        #expect(found == [a])
        #expect(found.first?.count == 35)
    }

    // MARK: - defaultFiles()

    @Test func defaultFilesFindsBundleByID() throws {
        let tmp = TempDir()
        let apps = tmp.url.appendingPathComponent("Applications", isDirectory: true)
        let home = tmp.url.appendingPathComponent("home", isDirectory: true)
        let appBundle = apps.appendingPathComponent("Other.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.google.antigravity-ide"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: appBundle.appendingPathComponent("Info.plist"))

        // Enumerated bundle URLs come back under /private/var while injected ones stay /var;
        // normalize by dropping the /private prefix before comparing.
        func canon(_ p: String) -> String { p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : p }
        let result = AntigravityClientDiscovery.defaultFiles(home: home, applicationDirectories: [apps])
        let paths = Set(result.map { canon($0.path) })
        let bundleRoot = canon(apps.appendingPathComponent("Other.app").path)
        for rel in AntigravityClientDiscovery.relativePaths {
            #expect(paths.contains(bundleRoot + "/" + rel))
        }
        #expect(result.last.map { canon($0.path) } == canon(home.appendingPathComponent(".local/bin/agy").path))
    }

    // MARK: - scanning / probing

    @Test func fileWithoutClientIDSkipped() async {
        let tmp = TempDir()
        // Candidate present, but no client id → not scanned.
        let f = tmp.write("bin", Data(("junk " + Self.fakeSecret()).utf8))
        let (d, t) = discovery(files: [f], accept: [Self.fakeSecret()])
        await #expect(throws: GoogleOAuthError.clientUnavailable) { _ = try await d.client() }
        #expect(t.requests.isEmpty)
    }

    @Test func worldWritableFileSkipped() async {
        let tmp = TempDir()
        let secret = Self.fakeSecret()
        let f = tmp.write("bin", Self.blob([secret]), mode: 0o666)
        let (d, t) = discovery(files: [f], accept: [secret])
        await #expect(throws: GoogleOAuthError.clientUnavailable) { _ = try await d.client() }
        #expect(t.requests.isEmpty)
    }

    @Test func noCandidatesThrowsClientUnavailable() async {
        let tmp = TempDir()
        let f = tmp.write("bin", Self.blob([]))
        let (d, t) = discovery(files: [f])
        await #expect(throws: GoogleOAuthError.clientUnavailable) { _ = try await d.client() }
        #expect(t.requests.isEmpty)
    }

    @Test func picksCandidateThatProbesTrue() async throws {
        let tmp = TempDir()
        let wrong = Self.fakeSecret("a"), right = Self.fakeSecret("b")
        let f = tmp.write("bin", Self.blob([wrong, right]))
        let cache = InMemoryCredentialStore()
        let (d, t) = discovery(files: [f], accept: [right], cache: cache)
        let client = try await d.client()
        #expect(client.secret.reveal() == right)
        #expect(t.requests.count == 2)
        #expect(try cache.read(AntigravityClientDiscovery.cacheID)?.access.reveal() == right)
    }

    @Test func probesOnlyGoogleTokenEndpoint() async throws {
        let tmp = TempDir()
        let wrong = Self.fakeSecret("a"), right = Self.fakeSecret("b")
        let f = tmp.write("bin", Self.blob([wrong, right]))
        let (d, t) = discovery(files: [f], accept: [right])
        _ = try await d.client()
        for (i, req) in t.requests.enumerated() {
            #expect(req.httpMethod == "POST")
            #expect(req.url?.absoluteString == GoogleOAuth.tokenURL.absoluteString)
            #expect(t.secret(i) != nil)
        }
        // The right secret appears only in the token request body, nowhere in the URL.
        #expect(t.requests.allSatisfy { !($0.url?.absoluteString.contains(right) ?? false) })
    }

    @Test func candidateCapIsFour() async {
        let tmp = TempDir()
        let secrets = (0 ..< 6).map { Self.fakeSecret(Character(UnicodeScalar(UInt8(97 + $0)))) }
        let f = tmp.write("bin", Self.blob(secrets))
        let (d, t) = discovery(files: [f]) // none accepted
        await #expect(throws: GoogleOAuthError.clientUnavailable) { _ = try await d.client() }
        #expect(t.requests.count == 4)
    }

    @Test func keychainCacheSkipsProbe() async throws {
        let secret = Self.fakeSecret()
        let cache = InMemoryCredentialStore()
        try cache.write(
            Credential(kind: .google, access: Secret(secret), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [], remoteAccountID: Self.clientID),
            for: AntigravityClientDiscovery.cacheID,
            label: "x"
        )
        // A file path that would crash the scan if read, proving the cache short-circuits it.
        let bogus = URL(fileURLWithPath: "/nonexistent/should-not-be-read")
        let (d, t) = discovery(files: [bogus], cache: cache)
        let client = try await d.client()
        #expect(client.secret.reveal() == secret)
        #expect(t.requests.isEmpty)
    }

    @Test func failedDiscoveryNotRetriedThisLaunch() async {
        let tmp = TempDir()
        let f = tmp.write("bin", Self.blob([])) // no candidates
        let (d, t) = discovery(files: [f])
        await #expect(throws: GoogleOAuthError.clientUnavailable) { _ = try await d.client() }
        await #expect(throws: GoogleOAuthError.clientUnavailable) { _ = try await d.client() }
        #expect(t.requests.isEmpty)
    }

    @Test func concurrentCallsShareOneDiscovery() async throws {
        let tmp = TempDir()
        let wrong = Self.fakeSecret("a"), right = Self.fakeSecret("b")
        let f = tmp.write("bin", Self.blob([wrong, right]))
        let (d, t) = discovery(files: [f], accept: [right])
        async let a = d.client()
        async let b = d.client()
        let (c1, c2) = try await (a, b)
        #expect(c1.secret.reveal() == right)
        #expect(c2.secret.reveal() == right)
        // One discovery: wrong(401) + right(400) = 2 requests, not 4.
        #expect(t.requests.count == 2)
    }

    @Test func invalidateClearsCache() async throws {
        let tmp = TempDir()
        let secret = Self.fakeSecret()
        let f = tmp.write("bin", Self.blob([secret]))
        let cache = InMemoryCredentialStore()
        let (d, _) = discovery(files: [f], accept: [secret], cache: cache)
        _ = try await d.client()
        #expect(try cache.read(AntigravityClientDiscovery.cacheID) != nil)
        await d.invalidate()
        #expect(try cache.read(AntigravityClientDiscovery.cacheID) == nil)
    }

    @Test func clientDescriptionRedacted() async throws {
        let tmp = TempDir()
        let secret = Self.fakeSecret("z")
        let f = tmp.write("bin", Self.blob([secret]))
        let (d, _) = discovery(files: [f], accept: [secret])
        let client = try await d.client()
        var dumped = ""
        dump(client, to: &dumped)
        #expect(!String(describing: client).contains(secret))
        #expect(!String(reflecting: client).contains(secret))
        #expect(!dumped.contains(secret))
    }
}
