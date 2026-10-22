import Foundation
import Testing
@testable import UsageCore

private struct FakeReader: ClaudeCodeLoginReading {
    let result: Result<ClaudeCodeLogin, ClaudeCodeKeychainError>
    func read() throws -> ClaudeCodeLogin { try result.get() }
}

private final class CountingTransport: HTTPTransport, @unchecked Sendable {
    let status: Int
    let body: Data
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    init(status: Int, body: Data = Data()) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _count += 1 }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct ClaudeCodeLocalTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func body(expiresMs: Double?) -> Data {
        let exp = expiresMs.map { ",\"expiresAt\":\(Int64($0))" } ?? ""
        return Data(#"{"claudeAiOauth":{"accessToken":"fake-access","refreshToken":"fake-r","subscriptionType":"max","scopes":["user:profile"]\#(exp)},"mcpOAuth":{}}"#.utf8)
    }

    @Test func parsesOnlyNeededFields() throws {
        let l = try ClaudeCodeLogin.parse(Self.body(expiresMs: 1_800_000_000_000))
        #expect(l.access.reveal() == "fake-access")
        #expect(l.subscriptionType == "max")
        #expect(l.expiresAt == Self.now)
        // No stored property can hold a refresh token.
        #expect(!Mirror(reflecting: l).children.contains { ($0.label ?? "").lowercased().contains("refresh") })
        #expect(!String(describing: l).contains("fake-r"))
    }

    @Test func malformedAndMissing() {
        #expect(throws: ClaudeCodeKeychainError.malformed) { try ClaudeCodeLogin.parse(Data("{}".utf8)) }
        #expect(throws: ClaudeCodeKeychainError.malformed) { try ClaudeCodeLogin.parse(Data("x".utf8)) }
    }

    @Test func expiryUsesFiveMinuteMargin() {
        let mk = { (d: TimeInterval) in ClaudeCodeLogin(access: Secret("x"), expiresAt: Self.now.addingTimeInterval(d), subscriptionType: nil) }
        #expect(mk(299).isExpired(now: Self.now))
        #expect(mk(300).isExpired(now: Self.now))
        #expect(!mk(301).isExpired(now: Self.now))
        #expect(mk(-10).isExpired(now: Self.now))
        #expect(!ClaudeCodeLogin(access: Secret("x"), expiresAt: nil, subscriptionType: nil).isExpired(now: Self.now))
    }

    @Test func defaultAccountRule() {
        #expect(ClaudeCodeKeychainReader.defaultAccount("ckuo") == "ckuo")
        #expect(ClaudeCodeKeychainReader.defaultAccount("a b") == "claude-code-user")
        #expect(ClaudeCodeKeychainReader.defaultAccount("") == "claude-code-user")
    }

    private func client(_ r: Result<ClaudeCodeLogin, ClaudeCodeKeychainError>, _ t: CountingTransport) -> AccountClient {
        AccountClient(id: .claudeCodeLocal, provider: ClaudeProvider(), http: HTTPClient(transport: t), store: InMemoryCredentialStore(),
                      clock: ContinuousClock(), now: { Self.now }, claudeCode: FakeReader(result: r))
    }

    @Test func statusesWithoutNetwork() async {
        let t = CountingTransport(status: 200)
        #expect(await client(.failure(.notFound), t).fetch() == .failure(.claudeCodeNotSignedIn))
        #expect(await client(.failure(.userCanceled), t).fetch() == .failure(.claudeCodeDenied))
        let expired = ClaudeCodeLogin(access: Secret("x"), expiresAt: Self.now.addingTimeInterval(60), subscriptionType: nil)
        #expect(await client(.success(expired), t).fetch() == .failure(.claudeCodeExpired))
        #expect(t.count == 0)
    }

    @Test func unauthorizedIsExpiredWithoutRetry() async throws {
        let t = CountingTransport(status: 401)
        let ok = ClaudeCodeLogin(access: Secret("x"), expiresAt: Self.now.addingTimeInterval(3600), subscriptionType: nil)
        let store = InMemoryCredentialStore()
        let c = AccountClient(id: .claudeCodeLocal, provider: ClaudeProvider(), http: HTTPClient(transport: t), store: store,
                              clock: ContinuousClock(), now: { Self.now }, claudeCode: FakeReader(result: .success(ok)))
        #expect(await c.fetch() == .failure(.claudeCodeExpired))
        #expect(t.count == 1)
        #expect(try store.allAccountIDs().isEmpty)
    }

    @Test func deniedStopsFurtherReads() async {
        let c = client(.failure(.userCanceled), CountingTransport(status: 200))
        _ = await c.fetch()
        #expect(await c.fetch() == .failure(.claudeCodeDenied))
    }

    /// The reader exposes no write API: its source has no Keychain write, ACL, subprocess, or refresh-token path.
    @Test func readerSourceIsReadOnly() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageCore/Storage/ClaudeCodeKeychainReader.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        for banned in ["SecItemAdd", "SecItemUpdate", "SecItemDelete", "SecKeychain", "SecAccess", "kSecValueData", "Process(", "/usr/bin/security", "refreshToken"] {
            #expect(!src.contains(banned), "found \(banned)")
        }
        #expect(src.contains("SecItemCopyMatching"))
    }
}
