import Foundation
import Testing
@testable import UsageCore

/// Manual time source: tests advance it explicitly.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
}

final class CountingProvider: UsageProvider, @unchecked Sendable {
    let kind: ProviderKind = .claude
    let minimumInterval: Duration = .seconds(60)
    private let lock = NSLock()
    private var _fetches: [String] = []
    var failNext = false
    var fetches: [String] { lock.withLock { _fetches } }
    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        let fail = lock.withLock { () -> Bool in
            _fetches.append(credential.access.reveal())
            defer { failNext = false }
            return failNext
        }
        if fail { throw ProviderError.transport(host: "down") }
        return UsageSnapshot(accountID: AccountID(kind: .claude, remoteID: "x"), fetchedAt: Date(), meters: [])
    }
    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? { nil }
}

/// Signed in, but the server returned no trustworthy quota.
struct QuotaUnavailableProvider: UsageProvider {
    let kind: ProviderKind = .claude
    let minimumInterval: Duration = .seconds(60)
    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot { throw QuotaError.unavailable }
    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? { nil }
}

final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var _r: [(AccountID, FetchOutcome)] = []
    func add(_ id: AccountID, _ o: FetchOutcome) { lock.withLock { _r.append((id, o)) } }
    var all: [(AccountID, FetchOutcome)] { lock.withLock { _r } }
}

struct PollerTests {
    let clock = TestClock()
    let provider = CountingProvider()
    let results = Results()

    func ids(_ n: Int) -> [AccountID] { (0..<n).map { AccountID(kind: .claude, remoteID: "acct-\($0)") } }

    func make(_ n: Int) throws -> Poller {
        let store = InMemoryCredentialStore()
        let clock = clock
        var clients: [AccountClient] = []
        for id in ids(n) {
            try store.write(Credential(kind: .claude, access: Secret(id.rawValue), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: id, label: "t")
            clients.append(AccountClient(id: id, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { clock.now }))
        }
        let results = results
        return Poller(clients: clients, clock: ContinuousClock(), now: { clock.now }, jitter: { 0 }) { results.add($0, $1) }
    }

    @Test func allDueAccountsFetchedPerTick() async throws {
        let p = try make(3)
        clock.advance(300)  // past every stagger offset
        await p.tick()
        #expect(Set(provider.fetches) == Set(ids(3).map(\.rawValue)))
        #expect(provider.fetches.count == 3)
    }

    @Test func staggerSpreads() {
        let offsets = ids(6).map { staggerOffset(for: $0, interval: .seconds(300)) }
        #expect(Set(offsets).count == 6)
        #expect(offsets.allSatisfy { $0 >= .zero && $0 < .seconds(300) })
        #expect(offsets == ids(6).map { staggerOffset(for: $0, interval: .seconds(300)) })
    }

    @Test func foregroundUsesUserInterval() async throws {
        #expect(PollSchedule(userInterval: .seconds(90), isForeground: true).effectiveInterval(floor: .seconds(60)) == .seconds(90))
        #expect(PollSchedule(userInterval: .seconds(10), isForeground: true).effectiveInterval(floor: .seconds(60)) == .seconds(60))
        let p = try make(1)
        await p.setForeground(true)  // immediate fetch on open
        #expect(provider.fetches.count == 1)
        clock.advance(59); await p.tick()
        #expect(provider.fetches.count == 1)
        clock.advance(1); await p.tick()
        #expect(provider.fetches.count == 2)
    }

    @Test func backgroundFiveMinIncludingMenuBarAccount() async throws {
        #expect(PollSchedule(userInterval: .seconds(60), isForeground: false).effectiveInterval(floor: .seconds(60)) == .seconds(300))
        let p = try make(2)  // account 0 plays the menu bar account; no special case
        clock.advance(300); await p.tick()
        #expect(provider.fetches.count == 2)
        clock.advance(299); await p.tick()
        #expect(provider.fetches.count == 2)
        clock.advance(1); await p.tick()
        #expect(provider.fetches.count == 4)
    }

    @Test func floorEnforcedOnManualRefresh() async throws {
        let p = try make(1)
        await p.refreshAll(force: true)
        clock.advance(30)
        await p.refreshAll(force: true)
        #expect(provider.fetches.count == 1)
        clock.advance(30)
        await p.refreshAll(force: true)
        #expect(provider.fetches.count == 2)
    }

    @Test func wakeFiresOnceAfterSettle() async throws {
        let p = try make(2)
        await p.sleep()
        clock.advance(1000); await p.tick()
        #expect(provider.fetches.isEmpty)
        await p.wake()
        clock.advance(9); await p.tick()
        #expect(provider.fetches.isEmpty)
        clock.advance(1); await p.tick()
        #expect(provider.fetches.count == 2)
        await p.tick()
        #expect(provider.fetches.count == 2)
    }

    @Test func offlinePauses() async throws {
        let p = try make(1)
        await p.setOffline(true)
        clock.advance(1000); await p.tick()
        await p.refreshAll(force: true)
        #expect(provider.fetches.isEmpty)
        await p.setOffline(false)
        await p.tick()
        #expect(provider.fetches.count == 1)
    }

    @Test func respectsClientBackoff() async throws {
        let p = try make(1)
        await p.refreshAll(force: true)  // success sets nextEarliestFetch = now + 60
        clock.advance(60); await p.refreshAll(force: true)
        #expect(provider.fetches.count == 2)
    }

    @MainActor @Test func failureKeepsLastSnapshotMarkedStale() throws {
        let clock = clock
        let s = AppState(now: { clock.now })
        let id = ids(1)[0]
        let snap = UsageSnapshot(accountID: id, fetchedAt: clock.now, meters: [])
        s.apply(id, .success(snap))
        #expect(s.isFresh(id))
        s.apply(id, .failure(.offline))
        #expect(s.snapshots[id] == snap)
        #expect(s.statuses[id] == .offline)
        clock.advance(600)  // 2 × 300 s background interval
        #expect(!s.isFresh(id))
    }
}

/// Keychain stand-in whose read blocks until released (an unanswered access prompt).
final class BlockingStore: CredentialStoring, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    func read(_ id: AccountID) throws -> Credential? { gate.wait(); return nil }
    func write(_ c: Credential, for id: AccountID, label: String) throws {}
    func delete(_ id: AccountID) throws {}
    func allAccountIDs() throws -> [AccountID] { [] }
}

struct PollerStuckAccountTests {
    /// Regression: one Claude account stuck in a Keychain read starved every account after it
    /// (the Codex account never fetched). Other accounts must keep polling.
    @Test func stuckAccountDoesNotBlockOthers() async throws {
        let clock = TestClock()
        let provider = CountingProvider()
        let blocking = BlockingStore()
        let store = InMemoryCredentialStore()
        let stuck = AccountID(kind: .claude, remoteID: "stuck")
        let ok = AccountID(kind: .claude, remoteID: "ok")
        try store.write(Credential(kind: .claude, access: Secret("ok"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: ok, label: "t")
        let results = Results()
        let p = Poller(clients: [], clock: ContinuousClock(), now: { clock.now }, jitter: { 0 }) { results.add($0, $1) }
        await p.add(client: AccountClient(id: stuck, provider: provider, http: HTTPClient(), store: blocking, clock: ContinuousClock(), now: { clock.now }))
        await p.add(client: AccountClient(id: ok, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { clock.now }))
        let tick = Task { await p.tick() }
        for _ in 0..<200 where provider.fetches.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(provider.fetches == ["ok"])
        blocking.gate.signal()
        await tick.value
    }

    @Test func quotaErrorReportsQuotaUnavailable() async throws {
        let clock = TestClock()
        let id = AccountID(kind: .claude, remoteID: "acct-quota")
        let store = InMemoryCredentialStore()
        try store.write(Credential(kind: .claude, access: Secret("tok"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: id, label: "t")
        let client = AccountClient(id: id, provider: QuotaUnavailableProvider(), http: HTTPClient(), store: store, clock: ContinuousClock(), now: { clock.now })
        #expect(await client.fetch() == .failure(.quotaUnavailable))
        #expect(await client.status == .quotaUnavailable)
    }
}
