import Foundation
import Testing
@testable import UsageCore

struct CodexOwnedTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    let id = AccountID(kind: .codex, remoteID: "acct-1")
    let owned = CodexProvider(auth: nil)

    static func usage() throws -> String { String(decoding: try fixture("codex-plus"), as: UTF8.self) }
    static let tokenNew = (200, #"{"access_token":"tok-new","refresh_token":"ref-new"}"#, [String: String]())

    func cred(_ access: String = "tok-c", refresh: String? = "ref-old", account: String? = "acct-1", expiresAt: Date? = nil, earliest: Date? = nil) -> Credential {
        Credential(kind: .codex, access: Secret(access), refresh: refresh.map { Secret($0) }, expiresAt: expiresAt, refreshExpiresAt: nil, scopes: [], remoteAccountID: account, earliestRefreshAt: earliest)
    }

    func client(_ t: ScriptedTransport, _ store: InMemoryCredentialStore) -> AccountClient {
        AccountClient(id: id, provider: owned, http: HTTPClient(transport: t), store: store, clock: ContinuousClock(), now: { Self.now })
    }

    @Test func ownedFetchSendsBearerAndAccountHeader() async throws {
        let t = ScriptedTransport([(200, try Self.usage(), [:])])
        let s = try await owned.fetch(credential: cred(), http: HTTPClient(transport: t))
        #expect(!owned.isBorrowed)
        #expect(t.requests.count == 1)
        let r = t.requests[0]
        #expect(r.url?.host == "chatgpt.com")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok-c")
        #expect(r.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1")
        #expect(s.accountID == id)
        #expect(s.meters.map(\.label) == ["5-hour", "Weekly", "codex-mini, 5-hour"])
    }

    @Test func ownedMissingAccountIDIsInvalidGrant() async {
        let t = ScriptedTransport([])
        await #expect(throws: ProviderError.invalidGrant) {
            try await owned.fetch(credential: cred(account: nil), http: HTTPClient(transport: t))
        }
        #expect(t.requests.count == 0)
    }

    @Test func ownedUnauthorizedPropagates() async {
        let t = ScriptedTransport([(401, "", [:])])
        await #expect(throws: ProviderError.unauthorized) {
            try await owned.fetch(credential: cred(), http: HTTPClient(transport: t))
        }
        #expect(t.requests.count == 1)
    }

    @Test func snapshotCarriesNoEmailOrUserID() throws {
        let body = #"{"email":"pii@example.com","user_id":"user-PII","plan_type":"plus","rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":18000,"reset_at":1800003600}}}"#
        let s = try CodexProvider.decode(Data(body.utf8), accountID: id, now: Self.now)
        let dump = String(describing: s) + String(describing: s.rawUnknownKeys)
        #expect(!dump.contains("pii@example.com") && !dump.contains("user-PII"))
        #expect(!s.rawUnknownKeys.contains("email") && !s.rawUnknownKeys.contains("user_id"))
        let enc = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!enc.contains("pii@example.com") && !enc.contains("user-PII"))
    }

    @Test func clientRefreshesOwnedCodexOn401() async throws {
        let store = InMemoryCredentialStore()
        try store.write(cred("tok-old"), for: id, label: "x")
        let t = ScriptedTransport([(401, "", [:]), Self.tokenNew, (200, try Self.usage(), [:])])
        guard case .success = await client(t, store).fetch() else { Issue.record("expected success"); return }
        #expect(t.requests.count == 3)
        guard t.requests.count == 3 else { return }
        #expect(t.requests[1].url?.host == "auth.openai.com")
        #expect(t.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer tok-new")
        let saved = try #require(try store.read(id))
        #expect(saved.access.reveal() == "tok-new" && saved.refresh?.reveal() == "ref-new")
        #expect(saved.remoteAccountID == "acct-1")
    }

    @Test func clientOwnedCodexReusedRefreshNeedsLogin() async throws {
        let store = InMemoryCredentialStore()
        try store.write(cred("tok-old"), for: id, label: "x")
        let t = ScriptedTransport([(401, "", [:]), (400, #"{"error":"refresh_token_reused"}"#, [:])])
        #expect(await client(t, store).fetch() == .failure(.needsLogin))
        #expect(t.requests.count == 2)
    }

    @Test func proactiveRefreshHonoursEarliestRefreshAt() async throws {
        let store = InMemoryCredentialStore()
        // Expires in 60 s (inside the proactive window) but refresh not yet allowed: no token call.
        try store.write(cred(expiresAt: Self.now.addingTimeInterval(60), earliest: Self.now.addingTimeInterval(120)), for: id, label: "x")
        let t = ScriptedTransport([(200, try Self.usage(), [:])])
        guard case .success = await client(t, store).fetch() else { Issue.record("expected success"); return }
        #expect(t.requests.count == 1)
        #expect(t.requests.first?.url?.host == "chatgpt.com")
    }

    @Test func proactiveRefreshAfterEarliestRefreshAt() async throws {
        let store = InMemoryCredentialStore()
        try store.write(cred(expiresAt: Self.now.addingTimeInterval(60), earliest: Self.now.addingTimeInterval(-1)), for: id, label: "x")
        let t = ScriptedTransport([Self.tokenNew, (200, try Self.usage(), [:])])
        guard case .success = await client(t, store).fetch() else { Issue.record("expected success"); return }
        #expect(t.requests.count == 2)
        #expect(t.requests.first?.url?.host == "auth.openai.com")
    }

    @Test func borrowedModeUnchanged() async throws {
        let store = InMemoryCredentialStore()
        try store.write(cred(), for: id, label: "x")
        let t = ScriptedTransport([])
        let p = CodexProvider(auth: FailingLogin())
        #expect(p.isBorrowed)
        #expect(try await p.refresh(credential: cred(), http: HTTPClient(transport: t)) == nil)
        let c = AccountClient(id: id, provider: p, http: HTTPClient(transport: t), store: store, clock: ContinuousClock(), now: { Self.now })
        #expect(await c.fetch() == .failure(.codexNotSignedIn))
        #expect(t.requests.count == 0)
    }
}

private struct FailingLogin: CodexLoginSource {
    func login() throws -> CodexLogin { throw CodexAuthError.missing }
    func invalidate() {}
}
