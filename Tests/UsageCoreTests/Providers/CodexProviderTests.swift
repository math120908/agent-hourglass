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

/// Records requests; returns queued statuses (last repeats) with the codex-go body.
final class CodexTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int]
    private(set) var requests: [URLRequest] = []
    init(_ statuses: [Int] = [200]) { self.statuses = statuses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let status: Int = lock.withLock {
            requests.append(request)
            return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        }
        return (try fixture("codex-go"), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    var count: Int { lock.withLock { requests.count } }
}

struct CodexProviderTests {
    let id = AccountID(kind: .codex, remoteID: "acct-1")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func goPlanThirtyDayPrimary() throws {
        let s = try CodexProvider.decode(fixture("codex-go"), accountID: id, now: now)
        #expect(s.plan == "go")
        #expect(s.meters.count == 1)
        let m = s.meters[0]
        #expect(m.kind == .window && m.label == "30-day" && m.windowSeconds == 2_592_000)
        #expect(m.percentUsed == 12)
        #expect(m.resetsAt == Date(timeIntervalSince1970: 1_801_296_000))
        #expect(s.spend == nil)
        #expect(s.rawUnknownKeys == ["code_review_rate_limit", "model_usage", "promo", "rate_limit_reached_type"])
    }

    @Test func plusTwoWindowsAdditionalAndCredits() throws {
        let s = try CodexProvider.decode(fixture("codex-plus"), accountID: id, now: now)
        #expect(s.meters.map(\.label) == ["5-hour", "Weekly", "codex-mini, 5-hour"])
        #expect(s.spend == Money(usedMinor: 250, limitMinor: nil, currency: "credits", exponent: 0))
    }

    @Test func badShapes() {
        #expect(throws: ProviderError.self) { try CodexProvider.decode(Data("[]".utf8), accountID: id, now: now) }
        #expect(throws: ProviderError.self) { try CodexProvider.decode(Data(#"{"rate_limit":{"primary_window":null}}"#.utf8), accountID: id, now: now) }
    }

    @Test func windowLabels() {
        #expect(Meter.windowLabel(seconds: 18000) == "5-hour")
        #expect(Meter.windowLabel(seconds: 604_800) == "Weekly")
        #expect(Meter.windowLabel(seconds: 2_592_000) == "30-day")
        #expect(Meter.windowLabel(seconds: 172_800) == "2-day")
        #expect(Meter.windowLabel(seconds: 7200) == "2-hour")
        #expect(Meter.windowCaption(seconds: 2_592_000) == "30D")
        #expect(Meter.windowCaption(seconds: 18000) == "5H")
    }

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

    @Test func chatgptHostAllowed() { #expect(HTTPClient.authHosts.contains("chatgpt.com")) }

    @Test func cardAndIcon() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let go = try CodexProvider.decode(fixture("codex-go"), accountID: id, now: now)
        let card = CardModel.make(snapshot: go, status: .fresh, kind: .codex, now: now, calendar: c, locale: Locale(identifier: "en_US_POSIX"))
        #expect(card.headline?.label == "30-day")
        #expect(card.headline?.percentText == "12%")
        #expect(card.headline?.resetText.hasPrefix("Resets ") == true)
        #expect(card.headline?.paceTick != nil)
        #expect(card.secondary == nil)
        #expect(card.planTag == "Go")
        let plus = try CodexProvider.decode(fixture("codex-plus"), accountID: id, now: now)
        let pc = CardModel.make(snapshot: plus, status: .fresh, kind: .codex, now: now, calendar: c, locale: Locale(identifier: "en_US_POSIX"))
        #expect(pc.secondary == "Wk 55%")
        #expect(CardModel.make(snapshot: nil, status: .codexNotSignedIn, kind: .codex, now: now, calendar: c, locale: .current).statusChip == "Run `codex` to sign in")
        #expect(CardModel.make(snapshot: nil, status: .needsLogin, kind: .codex, now: now, calendar: c, locale: .current).statusChip == "Run `codex` to sign in")
        let icon = IconState.make(appState: [id: go], statuses: [id: .fresh], menuBarAccount: id, order: [id], now: now)
        #expect(icon.caption == "30D" && icon.percent == 12 && icon.pace != nil && icon.weekly == nil)
        let icon2 = IconState.make(appState: [id: plus], statuses: [id: .fresh], menuBarAccount: id, order: [id], now: now)
        #expect(icon2.caption == "5H" && icon2.weekly == 55)
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
        #expect(try store.allAccountIDs() == [id])
        #expect(await registry.accounts().isEmpty)
        #expect(try String(contentsOfFile: auth.path, encoding: .utf8) == codexAuthBody)
    }
}

@Suite struct CodexLoginSourceTests {
    let id = AccountID(kind: .codex, remoteID: "acct-1")
    static let login = CodexLogin(access: Secret("tok-synthetic"), accountID: "acct-1")

    func client(_ auth: (any CodexLoginSource)?, _ t: CodexTransport) -> AccountClient {
        AccountClient(id: id, provider: CodexProvider(auth: auth), http: HTTPClient(transport: t), store: InMemoryCredentialStore(), clock: ContinuousClock(), now: { Date() })
    }

    func service(_ auth: (any CodexLoginSource)?) throws -> AccountService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cxls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = InMemoryCredentialStore()
        let http = HTTPClient(transport: CodexTransport())
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }) { _, _ in }
        return AccountService(
            registry: AccountRegistry(directory: dir),
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
    }

    @Test func fakeLoginSendsHeaders() async throws {
        let t = CodexTransport()
        guard case .success = await client(FakeCodexLogin([.success(Self.login)]), t).fetch() else { Issue.record("expected success"); return }
        let r = try #require(t.requests.first)
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok-synthetic")
        #expect(r.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1")
    }

    @Test func unauthorizedInvalidatesOnce() async throws {
        let fake = FakeCodexLogin([.success(Self.login)])
        guard case .success = await client(fake, CodexTransport([401, 200])).fetch() else { Issue.record("expected success"); return }
        #expect(fake.invalidateCalls == 1)
        #expect(fake.loginCalls == 2)
    }

    @Test func nilSourceIsNotSignedIn() async throws {
        let t = CodexTransport()
        #expect(await client(nil, t).fetch() == .failure(.codexNotSignedIn))
        #expect(t.count == 0)
    }

    @Test func notChatGPTFromSource() async throws {
        let t = CodexTransport()
        #expect(await client(FakeCodexLogin([.failure(CodexAuthError.notChatGPT)]), t).fetch() == .failure(.codexNotSignedIn))
        #expect(t.count == 0)
    }

    @Test func addCodexUsesProtocol() async throws {
        let fake = FakeCodexLogin([.success(Self.login)])
        let id = try await service(fake).addCodex()
        #expect(id.rawValue == "codex:acct-1")
        #expect(fake.invalidateCalls == 1)
        #expect(fake.events.prefix(2) == ["invalidate", "login"])
        await #expect(throws: CodexAuthError.missing) { try await service(nil).addCodex() }
    }
}
