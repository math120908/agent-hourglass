import Foundation
import Testing
@testable import UsageCore

final class SvcEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _e: [String] = []
    func add(_ s: String) { lock.withLock { _e.append(s) } }
    var all: [String] { lock.withLock { _e } }
}

/// Records each write with whether the registry file already existed, so order is checkable.
final class SvcLoggingStore: CredentialStoring, @unchecked Sendable {
    let inner = InMemoryCredentialStore()
    let log: SvcEventLog
    let registryURL: URL
    private let lock = NSLock()
    private var _labels: [String] = []
    var labels: [String] { lock.withLock { _labels } }
    init(log: SvcEventLog, registryURL: URL) { self.log = log; self.registryURL = registryURL }
    func read(_ id: AccountID) throws -> Credential? { try inner.read(id) }
    func write(_ c: Credential, for id: AccountID, label: String) throws {
        let hasRegistry = (try? String(contentsOf: registryURL, encoding: .utf8))?.contains(id.rawValue) ?? false
        log.add(hasRegistry ? "keychain-after-registry" : "keychain")
        lock.withLock { _labels.append(label) }
        try inner.write(c, for: id, label: label)
    }
    func delete(_ id: AccountID) throws { log.add("keychain-delete"); try inner.delete(id) }
    func allAccountIDs() throws -> [AccountID] { try inner.allAccountIDs() }
}

final class SvcLoggingProvider: UsageProvider, @unchecked Sendable {
    let kind: ProviderKind = .claude
    let minimumInterval: Duration = .seconds(60)
    let log: SvcEventLog
    let registryURL: URL
    init(log: SvcEventLog, registryURL: URL) { self.log = log; self.registryURL = registryURL }
    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot {
        log.add(FileManager.default.fileExists(atPath: registryURL.path) ? "fetch" : "fetch-before-registry")
        return UsageSnapshot(accountID: AccountID(kind: .claude, remoteID: "x"), fetchedAt: Date(), meters: [])
    }
    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? { nil }
}

final class SvcFakeHistory: HistoryDeleting, @unchecked Sendable {
    let log: SvcEventLog
    init(log: SvcEventLog) { self.log = log }
    func deleteAccount(_ id: AccountID) async throws { log.add("history-delete:\(id.rawValue)") }
}

/// Fake login returning queued remote ids; optionally blocks until released.
final class SvcFakeLogin: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String]
    init(_ ids: [String]) { queue = ids }
    func next() -> String { lock.withLock { queue.removeFirst() } }
}

struct AccountServiceTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("acctsvc-\(UUID().uuidString)")
    let log = SvcEventLog()
    let logins = SvcEventLog()

    func make(_ ids: [String], gate: AsyncStream<Void>? = nil) throws -> (AccountService, SvcLoggingStore, AccountRegistry) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let registry = AccountRegistry(directory: dir)
        let store = SvcLoggingStore(log: log, registryURL: registry.url)
        let provider = SvcLoggingProvider(log: log, registryURL: registry.url)
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }) { _, _ in }
        let login = SvcFakeLogin(ids)
        let svc = AccountService(
            registry: registry,
            store: store,
            poller: poller,
            history: SvcFakeHistory(log: log),
            claudeLogin: { [logins] _, _ in
                logins.add("login")
                if let gate { for await _ in gate { break } }
                let id = login.next()
                return (Credential(kind: .claude, access: Secret("tok-\(id)"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), id)
            },
            makeClient: { id in AccountClient(id: id, provider: provider, http: HTTPClient(), store: store, clock: ContinuousClock(), now: { Date() }) }
        )
        return (svc, store, registry)
    }

    func cid(_ s: String) -> AccountID { AccountID(kind: .claude, remoteID: s) }

    @Test func addWritesKeychainThenRegistryThenFetch() async throws {
        let (svc, _, registry) = try make(["a"])
        let id = try await svc.addClaude(loginHint: nil)
        #expect(id == cid("a"))
        #expect(log.all == ["keychain", "fetch"])
        #expect(await registry.accounts().map(\.id) == [id])
    }

    @Test func existingIdIsReauth() async throws {
        let (svc, store, registry) = try make(["a", "a"])
        try await svc.addClaude(loginHint: nil)
        try await svc.addClaude(loginHint: nil)
        #expect(await registry.accounts().count == 1)
        #expect(try store.allAccountIDs() == [cid("a")])
    }

    @Test func reauthDifferentIdWritesNothing() async throws {
        let (svc, store, registry) = try make(["a", "b"])
        try await svc.addClaude(loginHint: nil)
        let before = try Data(contentsOf: registry.url)
        let writes = store.labels.count
        await #expect(throws: AccountServiceError.differentAccount) { try await svc.reauth(cid("a")) }
        #expect(store.labels.count == writes)
        #expect(try store.allAccountIDs() == [cid("a")])
        #expect(try store.read(cid("a"))?.access.reveal() == "tok-a")
        #expect(try Data(contentsOf: registry.url) == before)
    }

    @Test func removeDeletesKeychainRegistryHistory() async throws {
        let (svc, store, registry) = try make(["a"])
        try await svc.addClaude(loginHint: nil)
        try await svc.remove(cid("a"))
        #expect(try store.allAccountIDs().isEmpty)
        #expect(await registry.accounts().isEmpty)
        #expect(log.all.contains("history-delete:claude:a"))
    }

    @Test func removeMenuBarPromotesNext() async throws {
        let (svc, _, registry) = try make(["a", "b"])
        try await svc.addClaude(loginHint: nil)
        try await svc.addClaude(loginHint: nil)
        #expect(await registry.menuBarAccountID == cid("a"))
        try await svc.remove(cid("a"))
        #expect(await registry.menuBarAccountID == cid("b"))
    }

    @Test func removeLastClearsMenuBar() async throws {
        let (svc, _, registry) = try make(["a"])
        try await svc.addClaude(loginHint: nil)
        try await svc.remove(cid("a"))
        #expect(await registry.menuBarAccountID == nil)
    }

    @Test func orphanKeychainItemDeleted() async throws {
        let (svc, store, _) = try make(["a"])
        try await svc.addClaude(loginHint: nil)
        try store.inner.write(Credential(kind: .claude, access: Secret("x"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: cid("orphan"), label: "t")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [cid("a")])
    }

    @Test func reauthRefusesNonClaude() async throws {
        let (svc, _, registry) = try make(["x"])
        let id = AccountID(kind: .codex, remoteID: "x")
        try await registry.upsert(AccountEntry(id: id, kind: .codex, displayName: "Codex", remoteLogin: nil, order: 0, addedAt: Date(), status: "ok"))
        await #expect(throws: AccountServiceError.reauthUnsupported) { try await svc.reauth(id) }
        #expect(logins.all.isEmpty)
    }

    @Test func cleanupOrphansKeepsCodex() async throws {
        let (svc, store, _) = try make([])
        let codex = AccountID(kind: .codex, remoteID: "x")
        try store.inner.write(Credential(kind: .codex, access: Secret("x"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: codex, label: "t")
        try store.inner.write(Credential(kind: .claude, access: Secret("y"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: cid("y"), label: "t")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [codex])
    }

    @Test func labelHasNoDisplayName() async throws {
        let (svc, store, registry) = try make(["a", "a"])
        let id = try await svc.addClaude(loginHint: nil)
        try await registry.rename(id, to: "Work Secret Name")
        try await svc.reauth(id)
        #expect(store.labels == ["Claude Usage – claude #1", "Claude Usage – claude #1"])
    }

    @Test func concurrentSignInRejected() async throws {
        let (stream, cont) = AsyncStream<Void>.makeStream()
        let (svc, _, _) = try make(["a"], gate: stream)
        let first = Task { try await svc.addClaude(loginHint: nil) }
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: AccountServiceError.signInInProgress) { try await svc.addClaude(loginHint: nil) }
        cont.yield()
        #expect(try await first.value == cid("a"))
    }
}
