import Foundation
import Testing
@testable import UsageCore

/// Wraps an in-memory store; the first `failWrites` writes throw.
final class FlakyStore: CredentialStoring, @unchecked Sendable {
    let inner = InMemoryCredentialStore()
    private let lock = NSLock()
    private var failWrites: Int
    init(failWrites: Int) { self.failWrites = failWrites }
    func read(_ id: AccountID) throws -> Credential? { try inner.read(id) }
    func write(_ c: Credential, for id: AccountID, label: String) throws {
        let fail = lock.withLock { () -> Bool in
            guard failWrites > 0 else { return false }
            failWrites -= 1
            return true
        }
        if fail { throw CredentialStoreError.unexpected(status: -1) }
        try inner.write(c, for: id, label: label)
    }
    func delete(_ id: AccountID) throws { try inner.delete(id) }
    func allAccountIDs() throws -> [AccountID] { try inner.allAccountIDs() }
}

struct CrossProcessRefreshTests {
    let id = AccountID(kind: .claude, remoteID: "acct-42")
    let dir: URL
    let clock = TestClock()

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("xpr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func cred(_ tok: String, _ ref: String, expiresAt: Date? = nil) -> Credential {
        Credential(kind: .claude, access: Secret(tok), refresh: Secret(ref), expiresAt: expiresAt, refreshExpiresAt: nil, scopes: [])
    }

    func client(_ provider: UsageProvider, store: CredentialStoring, shared: SharedAccountState? = nil) -> AccountClient {
        let clock = clock
        return AccountClient(id: id, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { clock.now }, shared: shared ?? .inDirectory(dir))
    }

    func fetches(_ log: EventLog) -> [String] { log.events.filter { $0.hasPrefix("fetch:") } }

    @Test func rotatedByOtherProcessSkipsRefresh() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-1", "ref-1"), for: id, label: "t")
        provider.validToken = "tok-9"
        let inner = store.inner, id = id
        provider.onFetch = { tok in
            if tok == "tok-1" { try inner.write(Credential(kind: .claude, access: Secret("tok-9"), refresh: Secret("ref-9"), expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: id, label: "t") }
        }
        let o = await client(provider, store: store).fetch()
        guard case .success = o else { Issue.record("\(o)"); return }
        #expect(provider.refreshCount == 0)
        #expect(fetches(log) == ["fetch:tok-1", "fetch:tok-9"])
    }

    @Test func readsKeychainEachFetch() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-1", "ref-1"), for: id, label: "t")
        let c = client(provider, store: store)
        guard case .success = await c.fetch() else { Issue.record("first"); return }
        try store.inner.write(cred("tok-2", "ref-2"), for: id, label: "t")
        provider.validToken = "tok-2"
        clock.advance(61)
        guard case .success = await c.fetch() else { Issue.record("second"); return }
        #expect(fetches(log) == ["fetch:tok-1", "fetch:tok-2"])
        #expect(provider.refreshCount == 0)
    }

    @Test func twoClientsOneRefresh() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-old", "ref-1", expiresAt: clock.now.addingTimeInterval(-10)), for: id, label: "t")
        provider.refreshDelay = .milliseconds(200)
        let a = client(provider, store: store, shared: .inDirectory(dir))
        let b = client(provider, store: store, shared: .inDirectory(dir))
        async let oa = a.fetch()
        async let ob = b.fetch()
        let (ra, rb) = await (oa, ob)
        #expect(provider.refreshCount == 1)
        guard case .success = ra, case .success = rb else { Issue.record("\(ra) \(rb)"); return }
    }

    @Test func refreshUsesReReadRefreshToken() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-old", "ref-5"), for: id, label: "t")
        _ = await client(provider, store: store).fetch()
        #expect(provider.refreshTokensSeen == ["ref-5"])
    }

    @Test func lockReleasedBeforeUsageFetch() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-old", "ref-1", expiresAt: clock.now.addingTimeInterval(-10)), for: id, label: "t")
        let url = dir.appendingPathComponent("refresh.lock")
        let acquired = EventLog()
        provider.onFetch = { _ in
            if (try? await FileRefreshLock(url: url, timeout: .milliseconds(100)).withLock { true }) == true { acquired.add("ok") }
        }
        _ = await client(provider, store: store).fetch()
        #expect(provider.refreshCount == 1)
        #expect(acquired.events == ["ok"])
    }

    @Test func saveFailedKeepsRotatedCredentialInSharedMode() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-old", "ref-1"), for: id, label: "t")
        store.inner.writeError = CredentialStoreError.unexpected(status: -1)
        let c = client(provider, store: store)
        guard case .success = await c.fetch() else { Issue.record("first"); return }
        #expect(await c.saveFailed)
        clock.advance(61)
        guard case .success = await c.fetch() else { Issue.record("second"); return }
        #expect(fetches(log).last == "fetch:tok-2")
        provider.validToken = "tok-none"
        clock.advance(61)
        _ = await c.fetch()
        #expect(provider.refreshTokensSeen == ["ref-1", "ref-2"])
    }

    @Test func saveFailureBlocksOtherProcessRefresh() async throws {
        let la = EventLog(), pa = FakeProvider(log: la)
        let lb = EventLog(), pb = FakeProvider(log: lb)
        let store = FlakyStore(failWrites: 2)
        try store.inner.write(cred("tok-old", "ref-1"), for: id, label: "t")
        let a = client(pa, store: store, shared: .inDirectory(dir))
        guard case .success = await a.fetch() else { Issue.record("a"); return }
        #expect(await a.saveFailed)
        #expect(try store.read(id)?.access == Secret("tok-old"))
        let b = client(pb, store: store, shared: .inDirectory(dir))
        _ = await b.fetch()
        #expect(pb.refreshCount == 0)
        #expect(fetches(lb).isEmpty)
        // A retries the save on its next fetch, before any refresh.
        _ = await a.fetch()
        #expect(await !a.saveFailed)
        #expect(try store.read(id)?.access == Secret("tok-2"))
        #expect(pa.refreshCount == 1)
    }

    @Test func invalidGrantRereadsBeforeNeedsLogin() async throws {
        let log = EventLog(), provider = FakeProvider(log: log), store = LoggingStore(log: log)
        try store.inner.write(cred("tok-old", "ref-1"), for: id, label: "t")
        provider.validToken = "tok-7"
        provider.refreshError = .invalidGrant
        let inner = store.inner, id = id
        provider.onRefresh = {
            try? inner.write(Credential(kind: .claude, access: Secret("tok-7"), refresh: Secret("ref-7"), expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: id, label: "t")
        }
        let c = client(provider, store: store)
        let o = await c.fetch()
        guard case .success = o else { Issue.record("\(o)"); return }
        #expect(await c.status == .fresh)
        #expect(fetches(log) == ["fetch:tok-old", "fetch:tok-7"])
    }
}
