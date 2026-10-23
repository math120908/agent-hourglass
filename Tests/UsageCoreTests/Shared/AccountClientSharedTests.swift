import Foundation
import Testing
@testable import UsageCore

/// Throws `.rateLimited(retryAfter:)` once, then behaves like `FakeProvider`.
final class RateLimitedOnceProvider: UsageProvider, @unchecked Sendable {
    let kind: ProviderKind = .claude
    let minimumInterval: Duration = .seconds(60)
    let inner: FakeProvider
    let retryAfter: Duration
    private let lock = NSLock()
    private var thrown = false
    init(log: EventLog, retryAfter: Duration) {
        inner = FakeProvider(log: log)
        self.retryAfter = retryAfter
    }
    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        let first = lock.withLock { () -> Bool in defer { thrown = true }; return !thrown }
        if first {
            inner.log.add("fetch:\(credential.access.reveal())")
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        }
        return try await inner.fetch(credential: credential, http: http)
    }
    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? {
        try await inner.refresh(credential: credential, http: http)
    }
}

struct AccountClientSharedTests {
    let id = AccountID(kind: .claude, remoteID: "acct-42")
    let dir: URL
    let clock = TestClock()

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("acs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func client(_ provider: UsageProvider, log: EventLog, shared: SharedAccountState?) throws -> AccountClient {
        let store = LoggingStore(log: log)
        try store.inner.write(Credential(kind: .claude, access: Secret("tok-1"), refresh: Secret("ref-1"), expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: id, label: "t")
        let clock = clock
        return AccountClient(id: id, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { clock.now }, shared: shared)
    }

    func fetches(_ log: EventLog) -> Int { log.events.filter { $0.hasPrefix("fetch:") }.count }
    func snap(at d: Date) -> UsageSnapshot { UsageSnapshot(accountID: id, fetchedAt: d, meters: []) }

    @Test func freshCacheSkipsNetwork() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        let s = snap(at: clock.now.addingTimeInterval(-30))
        try shared.cache.write(s)
        let log = EventLog()
        let c = try client(FakeProvider(log: log), log: log, shared: shared)
        #expect(await c.fetch() == .success(s))
        #expect(fetches(log) == 0)
        #expect(await c.nextEarliestFetch == s.fetchedAt.addingTimeInterval(60))
        #expect(await c.status == .fresh)
    }

    @Test func staleCacheFetches() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        let s = snap(at: clock.now.addingTimeInterval(-61))
        try shared.cache.write(s)
        let log = EventLog()
        let c = try client(FakeProvider(log: log), log: log, shared: shared)
        guard case let .success(new) = await c.fetch() else { Issue.record("expected success"); return }
        #expect(fetches(log) == 1)
        #expect(shared.cache.read(id) == new)
        #expect(new != s)
    }

    @Test func futureFetchedAtIsNotFresh() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        try shared.cache.write(snap(at: clock.now.addingTimeInterval(3600)))
        let log = EventLog()
        let c = try client(FakeProvider(log: log), log: log, shared: shared)
        _ = await c.fetch()
        #expect(fetches(log) == 1)
    }

    @Test func sharedBackoffGates() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        let cached = snap(at: clock.now.addingTimeInterval(-600))
        try shared.cache.write(cached)
        let next = clock.now.addingTimeInterval(120)
        try shared.backoff.setNextAllowedFetch(next, for: id)
        let log = EventLog()
        let c = try client(FakeProvider(log: log), log: log, shared: shared)
        #expect(await c.fetch() == .failure(.rateLimited(retryAt: next)))
        #expect(fetches(log) == 0)
        #expect(await c.lastSnapshot == cached)
        #expect(await c.nextEarliestFetch == next)
    }

    @Test func rateLimitWritesSharedBackoff() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        let log = EventLog()
        let c = try client(RateLimitedOnceProvider(log: log, retryAfter: .seconds(90)), log: log, shared: shared)
        _ = await c.fetch()
        #expect(shared.backoff.nextAllowedFetch(id, now: clock.now) == clock.now.addingTimeInterval(90))
    }

    @Test func successWritesCacheAndNextAllowed() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        let log = EventLog()
        let c = try client(FakeProvider(log: log), log: log, shared: shared)
        guard case let .success(s) = await c.fetch() else { Issue.record("expected success"); return }
        #expect(s.accountID == id)
        #expect(shared.cache.read(id) == s)
        #expect(shared.backoff.nextAllowedFetch(id, now: clock.now) == clock.now.addingTimeInterval(60))
    }

    @Test func secondClientReusesFirstClientsFetch() async throws {
        let shared = SharedAccountState.inDirectory(dir)
        let log = EventLog()
        let provider = FakeProvider(log: log)
        // FakeProvider stamps fetchedAt with the wall clock; keep the test clock in step.
        let real = Date()
        clock.advance(real.timeIntervalSince(clock.now))
        let a = try client(provider, log: log, shared: shared)
        let b = try client(provider, log: log, shared: shared)
        _ = await a.fetch()
        clock.advance(1)
        guard case .success = await b.fetch() else { Issue.record("expected success"); return }
        #expect(fetches(log) == 1)
    }

    @Test func nilSharedTouchesNoFiles() async throws {
        let log = EventLog()
        let c = try client(FakeProvider(log: log), log: log, shared: nil)
        _ = await c.fetch()
        clock.advance(61)
        _ = await c.fetch()
        #expect(fetches(log) == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}
