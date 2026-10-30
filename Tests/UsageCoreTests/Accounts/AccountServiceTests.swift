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

    /// `store` carries Keychain items across a simulated relaunch (a fresh registry and service on the same dir).
    func make(_ ids: [String], gate: AsyncStream<Void>? = nil, store reused: SvcLoggingStore? = nil) throws -> (AccountService, SvcLoggingStore, AccountRegistry) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let registry = AccountRegistry(directory: dir)
        let store = reused ?? SvcLoggingStore(log: log, registryURL: registry.url)
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

    @Test func cleanupOrphansDeletesGoogle() async throws {
        let (svc, store, _) = try make([])
        let google = AccountID(kind: .google, remoteID: "x")
        let codex = AccountID(kind: .codex, remoteID: "y")
        try store.inner.write(Credential(kind: .google, access: Secret("x"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: google, label: "t")
        try store.inner.write(Credential(kind: .codex, access: Secret("y"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: codex, label: "t")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [codex])
    }

    @Test func cleanupSkippedWhenRegistryQuarantined() async throws {
        let (svc, store, registry) = try make([])
        try Data("{\"version\":1,\"accou".utf8).write(to: registry.url)
        _ = try await registry.load()
        try store.inner.write(Credential(kind: .claude, access: Secret("y"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: cid("y"), label: "t")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [cid("y")])
    }

    @Test func cleanupKeepsHiddenUndecodableEntry() async throws {
        let (svc, store, registry) = try make([])
        // A claude entry missing `status` fails per-entry decode and is kept hidden.
        let file: [String: Any] = ["version": 1, "accounts": [["id": "claude:h", "kind": "claude", "displayName": "H", "order": 0, "addedAt": "2023-11-14T22:13:20Z"]]]
        try JSONSerialization.data(withJSONObject: file).write(to: registry.url)
        #expect(try await registry.load().isEmpty)
        #expect(await registry.loadedCleanly)
        try store.inner.write(Credential(kind: .claude, access: Secret("h"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: cid("h"), label: "t")
        try store.inner.write(Credential(kind: .claude, access: Secret("o"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), for: cid("orphan"), label: "t")
        try await svc.cleanupOrphans()
        #expect(try store.allAccountIDs() == [cid("h")])
    }

    func claudeCred(_ s: String) -> Credential {
        Credential(kind: .claude, access: Secret(s), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
    }

    @Test func cleanupSkippedWhenRegistryUnreadable() async throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("accounts.json").path)
            try? FileManager.default.removeItem(at: dir)
        }
        let (svc, store, registry) = try make([])
        try await registry.upsert(AccountEntry(id: cid("a"), kind: .claude, displayName: "A", remoteLogin: nil, order: 0, addedAt: Date(), status: "ok"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: registry.url.path)
        #expect(try await registry.load().isEmpty)
        #expect(await !registry.loadedCleanly)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains("accounts.json"))
        #expect(!names.contains { $0.hasPrefix("accounts.json.bad-") })
        try store.inner.write(claudeCred("a"), for: cid("a"), label: "t")
        try store.inner.write(claudeCred("y"), for: cid("y"), label: "t")
        try await svc.cleanupOrphans()
        #expect(Set(try store.allAccountIDs()) == [cid("a"), cid("y")])
    }

    @Test func commitRefusesToOverwriteUnreadableFile() async throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent("accounts.json").path)
            try? FileManager.default.removeItem(at: dir)
        }
        let (_, _, registry) = try make([])
        try await registry.upsert(AccountEntry(id: cid("a"), kind: .claude, displayName: "A", remoteLogin: nil, order: 0, addedAt: Date(), status: "ok"))
        let before = try Data(contentsOf: registry.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: registry.url.path)
        _ = try await registry.load()
        await #expect(throws: AccountRegistryError.unreadableFile) {
            try await registry.upsert(AccountEntry(id: cid("b"), kind: .claude, displayName: "B", remoteLogin: nil, order: 0, addedAt: Date(), status: "ok"))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registry.url.path)
        #expect(try Data(contentsOf: registry.url) == before)
    }

    @Test func quarantineKeepsCleanupOffNextLaunch() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (svc1, store, registry1) = try make([])
        try Data("{\"version\":1,\"accou".utf8).write(to: registry1.url)
        _ = try await registry1.load()
        try store.inner.write(claudeCred("y"), for: cid("y"), label: "t")
        try await svc1.cleanupOrphans()
        let (svc2, _, registry2) = try make([], store: store)
        #expect(try await registry2.load().isEmpty)
        #expect(await !registry2.loadedCleanly)
        try await svc2.cleanupOrphans()
        #expect(try store.allAccountIDs() == [cid("y")])
    }

    @Test func quarantineKeepsCleanupOffAfterAddInSameLaunch() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (svc1, store, registry1) = try make(["a"])
        try Data("{\"version\":1,\"accou".utf8).write(to: registry1.url)
        _ = try await registry1.load()
        try store.inner.write(claudeCred("y"), for: cid("y"), label: "t")
        try await svc1.addClaude(loginHint: nil)
        let (svc2, _, registry2) = try make([], store: store)
        #expect(try await registry2.load().map(\.id) == [cid("a")])
        #expect(await !registry2.loadedCleanly)
        try await svc2.cleanupOrphans()
        #expect(Set(try store.allAccountIDs()) == [cid("a"), cid("y")])
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
