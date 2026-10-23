import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

/// Writes a synthetic auth.json into a fresh temp dir. Never touches ~/.codex.
func fakeCodexAuth(_ body: String, mode: Int16 = 0o600) throws -> CodexAuthSource {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("auth.json").path
    try body.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    return CodexAuthSource(path: path)
}

let codexAuthBody = #"{"auth_mode":"chatgpt","tokens":{"access_token":"tok-synthetic","account_id":"acct-1"}}"#

struct CodexAuthSourceTests {
    let id = AccountID(kind: .codex, remoteID: "acct-1")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func authParse() throws {
        let l = try CodexAuthSource.parse(Data(codexAuthBody.utf8))
        #expect(l.accountID == "acct-1" && l.access.reveal() == "tok-synthetic")
        #expect(throws: CodexAuthError.notChatGPT) { try CodexAuthSource.parse(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"x","tokens":null}"#.utf8)) }
        #expect(throws: CodexAuthError.malformed) { try CodexAuthSource.parse(Data(#"{"auth_mode":"chatgpt","tokens":{}}"#.utf8)) }
        #expect(!"\(l)".contains("tok-synthetic"))
    }

    @Test func authFileChecks() throws {
        #expect(throws: CodexAuthError.missing) { try CodexAuthSource(path: "/nonexistent/auth.json").login() }
        #expect(throws: CodexAuthError.untrusted) { try fakeCodexAuth(codexAuthBody, mode: 0o666).login() }
        #expect(try fakeCodexAuth(codexAuthBody).login().accountID == "acct-1")
    }

    @Test func authFileNeverWritten() async throws {
        let auth = try fakeCodexAuth(codexAuthBody)
        let before = try FileManager.default.attributesOfItem(atPath: auth.path)[.modificationDate] as? Date
        let t = CodexTransport([401])
        _ = await client(auth, t).fetch()
        #expect(try String(contentsOfFile: auth.path, encoding: .utf8) == codexAuthBody)
        #expect(try FileManager.default.attributesOfItem(atPath: auth.path)[.modificationDate] as? Date == before)
    }

    func client(_ auth: CodexAuthSource, _ t: CodexTransport, store: CredentialStoring = InMemoryCredentialStore()) -> AccountClient {
        AccountClient(id: id, provider: CodexProvider(auth: auth), http: HTTPClient(transport: t), store: store, clock: ContinuousClock(), now: { Date() })
    }

    @Test func fetchSendsHeadersToChatGPT() async throws {
        let t = CodexTransport()
        let store = InMemoryCredentialStore()
        let c = client(try fakeCodexAuth(codexAuthBody), t, store: store)
        guard case let .success(s) = await c.fetch() else { Issue.record("expected success"); return }
        #expect(s.accountID == id)
        let r = try #require(t.requests.first)
        #expect(r.url == CodexProvider.usageURL)
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok-synthetic")
        #expect(r.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1")
        #expect(try store.allAccountIDs().isEmpty)
        let wait = await c.nextEarliestFetch.timeIntervalSinceNow
        #expect(wait > 290 && wait <= 300)
    }

    @Test func unauthorizedRereadsOnceThenNeedsLogin() async throws {
        let t = CodexTransport([401])
        let c = client(try fakeCodexAuth(codexAuthBody), t)
        #expect(await c.fetch() == .failure(.needsLogin))
        #expect(t.count == 2)
    }

    @Test func unauthorizedThenOkRecovers() async throws {
        let t = CodexTransport([401, 200])
        guard case .success = await client(try fakeCodexAuth(codexAuthBody), t).fetch() else { Issue.record("expected success"); return }
        #expect(t.count == 2)
    }

    @Test func notSignedInStatuses() async throws {
        let t = CodexTransport()
        #expect(await client(CodexAuthSource(path: "/nonexistent/auth.json"), t).fetch() == .failure(.codexNotSignedIn))
        let apikey = try fakeCodexAuth(#"{"auth_mode":"apikey","tokens":null}"#)
        #expect(await client(apikey, t).fetch() == .failure(.codexNotSignedIn))
        #expect(t.count == 0)
    }

    @Test func rateLimitedBacksOff() async throws {
        let c = client(try fakeCodexAuth(codexAuthBody), CodexTransport([429]))
        guard case .failure(.rateLimited) = await c.fetch() else { Issue.record("expected rateLimited"); return }
    }

}

struct CodexAccountServiceTests {
    @Test func addRemoveCleanup() async throws {
        let auth = try fakeCodexAuth(codexAuthBody)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cxsvc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let registry = AccountRegistry(directory: dir)
        let store = InMemoryCredentialStore()
        let http = HTTPClient(transport: CodexTransport())
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }) { _, _ in }
        let svc = AccountService(
            registry: registry,
            store: store,
            poller: poller,
            history: SvcFakeHistory(log: SvcEventLog()),
            claudeLogin: { _, _ in throw AccountServiceError.unknownAccount },
            makeClient: { id in
                AccountClient(id: id, provider: CodexProvider(auth: auth), http: http, store: store, clock: ContinuousClock(), now: { Date() })
            },
            http: http,
            codexAuth: auth
        )
        let id = try await svc.addCodex()
        #expect(id.rawValue == "codex:acct-1" && id.kind == .codex)
        #expect(await registry.accounts().first?.kind == .codex)
        #expect(try store.allAccountIDs().isEmpty)
        try store.write(CodexProvider.borrowed, for: id, label: "x")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [id])
        try await svc.remove(id)
        #expect(try store.allAccountIDs().isEmpty)
        #expect(await registry.accounts().isEmpty)
        #expect(try String(contentsOfFile: auth.path, encoding: .utf8) == codexAuthBody)
    }
}
