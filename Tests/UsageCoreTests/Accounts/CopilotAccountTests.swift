import Foundation
import Testing
@testable import UsageCore

private let ghToken = "gho_" + String(repeating: "y", count: 36)

/// Fake gh that appends one line to `calls` per invocation. Never a real gh.
private struct CountingGh {
    let dir: URL
    init(_ body: String = "echo \(ghToken)") throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cpgh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("gh").path
        try "#!/bin/sh\necho x >> '\(dir.path)/calls'\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
    var source: GhTokenSource { GhTokenSource(candidates: [dir.appendingPathComponent("gh").path]) }
    var calls: Int {
        ((try? String(contentsOf: dir.appendingPathComponent("calls"), encoding: .utf8)) ?? "")
            .split(separator: "\n").count
    }
}

/// Mock transport returning queued statuses (last one repeats); `/user` gets a numeric id.
private final class QueueTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int]
    private(set) var paths: [String] = []
    let userID: Int
    init(_ statuses: [Int] = [200], userID: Int = 4242) { self.statuses = statuses; self.userID = userID }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let status: Int = lock.withLock {
            paths.append(path)
            if path == "/user" { return 200 }
            return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        }
        let body = path == "/user"
            ? Data(#"{"login":"renamed","id":\#(userID)}"#.utf8)
            : try fixture("copilot-individual")
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
    var copilotCalls: Int { lock.withLock { paths.filter { $0 != "/user" }.count } }
}

struct CopilotAccountTests {
    let id = AccountID(kind: .copilot, remoteID: "4242")

    private func client(_ gh: GhTokenSource, _ t: QueueTransport, store: CredentialStoring = InMemoryCredentialStore()) -> AccountClient {
        AccountClient(
            id: id,
            provider: CopilotProvider(),
            http: HTTPClient(transport: t),
            store: store,
            clock: ContinuousClock(),
            now: { Date() },
            tokenSource: gh,
            login: "alice"
        )
    }

    @Test func firstFetchReadsGhOnce() async throws {
        let gh = try CountingGh()
        let out = await client(gh.source, QueueTransport()).fetch()
        guard case let .success(s) = out else { Issue.record("\(out)"); return }
        #expect(s.accountID == id)
        #expect(gh.calls == 1)
    }

    @Test func laterFetchesReuseCache() async throws {
        let gh = try CountingGh()
        let c = client(gh.source, QueueTransport())
        _ = await c.fetch()
        _ = await c.fetch()
        _ = await c.fetch()
        #expect(gh.calls == 1)
    }

    @Test func unauthorizedRereadsOnceThenNeedsLogin() async throws {
        let gh = try CountingGh()
        let t = QueueTransport([401])
        let c = client(gh.source, t)
        #expect(await c.fetch() == .failure(.needsLogin))
        #expect(gh.calls == 2)
        #expect(t.copilotCalls == 2)
        #expect(await c.status == .needsLogin)
    }

    @Test func unauthorizedThenOkRecovers() async throws {
        let gh = try CountingGh()
        let c = client(gh.source, QueueTransport([401, 200]))
        guard case .success = await c.fetch() else { Issue.record("expected success"); return }
        #expect(gh.calls == 2)
    }

    @Test func ghMissingStatus() async throws {
        let c = client(GhTokenSource(candidates: ["/nonexistent/gh"]), QueueTransport())
        #expect(await c.fetch() == .failure(.ghMissing))
    }

    @Test func loginRemovedStatus() async throws {
        let gh = try CountingGh("exit 1")
        #expect(await client(gh.source, QueueTransport()).fetch() == .failure(.ghLoginRemoved))
    }

    @Test func noKeychainWrite() async throws {
        let gh = try CountingGh()
        let store = InMemoryCredentialStore()
        _ = await client(gh.source, QueueTransport([401, 200]), store: store).fetch()
        #expect(try store.allAccountIDs().isEmpty)
    }

    private func service(_ gh: CountingGh, _ t: QueueTransport, store: InMemoryCredentialStore) throws -> (AccountService, AccountRegistry) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cpsvc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let registry = AccountRegistry(directory: dir)
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }) { _, _ in }
        let src = gh.source
        let http = HTTPClient(transport: t)
        let svc = AccountService(
            registry: registry,
            store: store,
            poller: poller,
            history: SvcFakeHistory(log: SvcEventLog()),
            claudeLogin: { _, _ in throw AccountServiceError.unknownAccount },
            makeClient: { id in
                AccountClient(id: id, provider: CopilotProvider(), http: http, store: store, clock: ContinuousClock(), now: { Date() }, tokenSource: src, login: "alice")
            },
            ghTokens: src,
            http: http
        )
        return (svc, registry)
    }

    @Test func idFromNumericUserId() async throws {
        let gh = try CountingGh()
        let store = InMemoryCredentialStore()
        let (svc, registry) = try service(gh, QueueTransport(), store: store)
        let added = try await svc.addCopilot(login: "alice")
        #expect(added == id)
        let again = try await svc.addCopilot(login: "alice-renamed")
        #expect(again == id)
        let entries = await registry.accounts()
        #expect(entries.count == 1)
        #expect(entries.first?.remoteLogin == "alice-renamed")
        #expect(try store.allAccountIDs().isEmpty)
    }

    @Test func removeSpawnsNoGh() async throws {
        let gh = try CountingGh()
        let store = InMemoryCredentialStore()
        let (svc, registry) = try service(gh, QueueTransport(), store: store)
        try await svc.addCopilot(login: "alice")
        let before = gh.calls
        try await svc.remove(id)
        #expect(gh.calls == before)
        #expect(await registry.accounts().isEmpty)
    }

    @Test func cleanupKeepsCopilot() async throws {
        let gh = try CountingGh()
        let store = InMemoryCredentialStore()
        let (svc, _) = try service(gh, QueueTransport(), store: store)
        try store.write(CopilotAccountTests.cred, for: id, label: "x")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [id])
    }

    static let cred = Credential(kind: .copilot, access: Secret("t"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
}

struct CopilotHistoryReproTests {
    @Test func addCopilotRecordsSample() async throws {
        let gh = try CountingGh()
        let t = QueueTransport()
        let store = InMemoryCredentialStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cprec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let history = try HistoryStore(url: dir.appendingPathComponent("h.sqlite"))
        let results = SvcEventLog()
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }, recorder: history) { id, o in
            results.add("\(id.rawValue) \(o)")
        }
        let src = gh.source
        let http = HTTPClient(transport: t)
        let svc = AccountService(
            registry: AccountRegistry(directory: dir),
            store: store,
            poller: poller,
            history: history,
            claudeLogin: { _, _ in throw AccountServiceError.unknownAccount },
            makeClient: { id in
                AccountClient(id: id, provider: CopilotProvider(), http: http, store: store, clock: ContinuousClock(), now: { Date() }, tokenSource: src, login: "alice")
            },
            ghTokens: src,
            http: http
        )
        let id = try await svc.addCopilot(login: "alice")
        #expect(t.copilotCalls == 1)
        #expect(!results.all.isEmpty)
        let rows = try await HistoryQuery(store: history).series(account: id, range: DateInterval(start: Date().addingTimeInterval(-3600), duration: 7200))
        #expect(!rows.isEmpty)
    }
}
