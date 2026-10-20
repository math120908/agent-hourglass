import Foundation
import Testing
@testable import UsageCore

/// Shared ordered event log so tests can check write-before-use ordering.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    func add(_ e: String) { lock.withLock { _events.append(e) } }
    var events: [String] { lock.withLock { _events } }
}

final class LoggingStore: CredentialStoring, @unchecked Sendable {
    let inner = InMemoryCredentialStore()
    let log: EventLog
    init(log: EventLog) { self.log = log }
    func read(_ id: AccountID) throws -> Credential? { try inner.read(id) }
    func write(_ c: Credential, for id: AccountID, label: String) throws {
        try inner.write(c, for: id, label: label)
        log.add("write:\(c.access.reveal())")
    }
    func delete(_ id: AccountID) throws { try inner.delete(id) }
    func allAccountIDs() throws -> [AccountID] { try inner.allAccountIDs() }
}

/// Mock provider: valid token is `tok-N`; refresh mints `tok-(N+1)` / `ref-(N+1)`.
final class FakeProvider: UsageProvider, @unchecked Sendable {
    let kind: ProviderKind = .claude
    let minimumInterval: Duration = .seconds(60)
    private let lock = NSLock()
    let log: EventLog
    var validToken = "tok-1"
    var refreshCount = 0
    var refreshDelay: Duration = .zero
    var refreshError: ProviderError?
    var alwaysUnauthorized = false
    var refreshTokensSeen: [String] = []

    init(log: EventLog) { self.log = log }

    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        let tok = credential.access.reveal()
        log.add("fetch:\(tok)")
        let ok = lock.withLock { !alwaysUnauthorized && tok == validToken }
        guard ok else { throw ProviderError.unauthorized }
        return UsageSnapshot(accountID: AccountID(kind: .claude, remoteID: "unknown"), fetchedAt: Date(), meters: [])
    }

    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? {
        let (n, err) = lock.withLock { () -> (Int, ProviderError?) in
            refreshCount += 1
            refreshTokensSeen.append(credential.refresh?.reveal() ?? "nil")
            return (refreshCount + 1, refreshError)
        }
        if refreshDelay > .zero { try await Task.sleep(for: refreshDelay) }
        if let err { throw err }
        lock.withLock { validToken = "tok-\(n)" }
        log.add("refresh:tok-\(n)")
        return Credential(kind: .claude, access: Secret("tok-\(n)"), refresh: Secret("ref-\(n)"), expiresAt: Date().addingTimeInterval(3600), refreshExpiresAt: nil, scopes: [])
    }
}

struct RefreshLockTests {
    let id = AccountID(kind: .claude, remoteID: "acct-42")

    func make(token: String = "tok-1", expiresAt: Date? = nil) throws -> (AccountClient, FakeProvider, LoggingStore, EventLog) {
        let log = EventLog()
        let provider = FakeProvider(log: log)
        let store = LoggingStore(log: log)
        try store.inner.write(Credential(kind: .claude, access: Secret(token), refresh: Secret("ref-1"), expiresAt: expiresAt, refreshExpiresAt: nil, scopes: []), for: id, label: "t")
        let client = AccountClient(id: id, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { Date() })
        return (client, provider, store, log)
    }

    @Test func tenConcurrentCallersOneRefresh() async throws {
        let (client, provider, _, _) = try make(token: "tok-expired")
        provider.refreshDelay = .milliseconds(100)
        let outcomes = await withTaskGroup(of: FetchOutcome.self) { g in
            for _ in 0..<10 { g.addTask { await client.fetch() } }
            return await g.reduce(into: []) { $0.append($1) }
        }
        #expect(provider.refreshCount == 1)
        for o in outcomes {
            guard case let .success(s) = o else { Issue.record("expected success, got \(o)"); continue }
            #expect(s.accountID == id)
        }
    }

    @Test func unauthorizedRefreshRetry() async throws {
        let (client, provider, _, log) = try make(token: "tok-old")
        let o = await client.fetch()
        guard case .success = o else { Issue.record("\(o)"); return }
        #expect(provider.refreshCount == 1)
        #expect(log.events.filter { $0.hasPrefix("fetch") } == ["fetch:tok-old", "fetch:tok-2"])
        #expect(await client.status == .fresh)
    }

    @Test func secondUnauthorizedNeedsLogin() async throws {
        let (client, provider, _, log) = try make()
        provider.alwaysUnauthorized = true
        #expect(await client.fetch() == .failure(.needsLogin))
        #expect(provider.refreshCount == 1)
        #expect(log.events.filter { $0.hasPrefix("fetch") }.count == 2)
        // Polling stops: no further network.
        #expect(await client.fetch() == .failure(.needsLogin))
        #expect(log.events.filter { $0.hasPrefix("fetch") }.count == 2)
    }

    @Test func invalidGrantNeedsLogin() async throws {
        let (client, provider, _, _) = try make(token: "tok-old")
        provider.refreshError = .invalidGrant
        #expect(await client.fetch() == .failure(.needsLogin))
        #expect(await client.status == .needsLogin)
    }

    @Test func refreshPersistedBeforeUse() async throws {
        let (client, _, _, log) = try make(token: "tok-old")
        _ = await client.fetch()
        let e = log.events
        let w = try #require(e.firstIndex(of: "write:tok-2"))
        let f = try #require(e.firstIndex(of: "fetch:tok-2"))
        #expect(w < f)
    }

    @Test func writeFailureKeepsNewNeverOld() async throws {
        let (client, provider, store, _) = try make(token: "tok-old")
        store.inner.writeError = CredentialStoreError.unexpected(status: -1)
        let o = await client.fetch()
        guard case .success = o else { Issue.record("\(o)"); return }
        #expect(await client.status == .stale)
        #expect(await client.saveFailed)
        // Keychain still holds the old credential; memory holds the new one.
        #expect(try store.read(id)?.access == Secret("tok-old"))
        // Force another refresh: it must use the rotated refresh token, never ref-1.
        provider.validToken = "tok-none"
        _ = await client.fetch()
        #expect(provider.refreshTokensSeen == ["ref-1", "ref-2"])
        // Write recovers on a later fetch.
        store.inner.writeError = nil
        provider.validToken = "tok-3"
        _ = await client.fetch()
        #expect(await client.saveFailed == false)
        #expect(try store.read(id)?.access == Secret("tok-3"))
        #expect(await client.status == .fresh)
    }

    @Test func expiredOnArrivalRefreshesOnce() async throws {
        let (client, provider, _, log) = try make(token: "tok-old", expiresAt: Date().addingTimeInterval(-10))
        let o = await client.fetch()
        guard case .success = o else { Issue.record("\(o)"); return }
        #expect(provider.refreshCount == 1)
        #expect(log.events.filter { $0.hasPrefix("fetch") } == ["fetch:tok-2"])
    }

    @Test func lockSingleFlight() async throws {
        let lock = RefreshLock()
        let counter = EventLog()
        let cred = Credential(kind: .claude, access: Secret("a"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<10 {
                g.addTask {
                    _ = try? await lock.refresh {
                        counter.add("x")
                        try await Task.sleep(for: .milliseconds(100))
                        return cred
                    }
                }
            }
        }
        #expect(counter.events.count == 1)
    }
}

struct SaveFailedWiringTests {
    @MainActor @Test func keychainWriteFailureReachesAppState() async throws {
        let id = AccountID(kind: .claude, remoteID: "acct-7")
        let log = EventLog()
        let provider = FakeProvider(log: log)
        let store = LoggingStore(log: log)
        try store.inner.write(Credential(kind: .claude, access: Secret("tok-old"), refresh: Secret("ref-1"), expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: id, label: "t")
        store.inner.writeError = CredentialStoreError.unexpected(status: -1)
        let t = TimeBox()
        let client = AccountClient(id: id, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { t.now })
        let state = AppState()
        let poller = Poller(
            clients: [client],
            clock: ContinuousClock(),
            now: { t.now },
            jitter: { 0 },
            onSaveState: { id, failed in await MainActor.run { state.setSaveFailed(id, failed) } }
        ) { id, outcome in await MainActor.run { state.apply(id, outcome) } }
        await poller.refreshAll(force: true)
        #expect(state.saveFailed == [id])
        store.inner.writeError = nil
        t.advance(3600)
        await poller.refreshAll(force: true)
        #expect(state.saveFailed.isEmpty)
    }
}

private final class TimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date()
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t += s } }
}
