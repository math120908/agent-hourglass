import Foundation
import Testing
@testable import UsageCore

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
