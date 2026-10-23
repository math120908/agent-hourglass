import Foundation
import Testing
@testable import UsageCore

final class StoredLoginCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _n = 0
    func hit() { lock.withLock { _n += 1 } }
    var count: Int { lock.withLock { _n } }
}

struct StoredAddTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("storedadd-\(UUID().uuidString)")
    let log = SvcEventLog()
    let logins = StoredLoginCounter()

    func make(store: CredentialStoring? = nil, shared: SharedAccountState? = nil) throws -> (AccountService, SvcLoggingStore, AccountRegistry, CredentialStoring) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let registry = AccountRegistry(directory: dir)
        let logging = SvcLoggingStore(log: log, registryURL: registry.url)
        let used: CredentialStoring = store ?? logging
        let provider = SvcLoggingProvider(log: log, registryURL: registry.url)
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }) { _, _ in }
        let counter = logins
        let svc = AccountService(
            registry: registry,
            store: used,
            poller: poller,
            history: SvcFakeHistory(log: log),
            claudeLogin: { _, _ in counter.hit(); throw AccountServiceError.unknownAccount },
            makeClient: { id in AccountClient(id: id, provider: provider, http: HTTPClient(), store: used, clock: ContinuousClock(), now: { Date() }) },
            shared: shared
        )
        return (svc, logging, registry, used)
    }

    func cred(_ tok: String, kind: ProviderKind = .claude) -> Credential {
        Credential(kind: kind, access: Secret(tok), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
    }

    @Test func addClaudeWithCredentialWritesKeychainThenRegistryThenFetch() async throws {
        let (svc, store, registry, _) = try make()
        let id = try await svc.addClaude(credential: cred("t1"), remoteID: "uuid-1")
        #expect(id.rawValue == "claude:uuid-1")
        #expect(log.all == ["keychain", "fetch"])
        #expect(store.labels == ["Claude Usage – claude #1"])
        #expect(await registry.accounts().map(\.id) == [id])
    }

    @Test func addClaudeWithCredentialTwiceIsReauth() async throws {
        let (svc, store, registry, _) = try make()
        let id = try await svc.addClaude(credential: cred("t1"), remoteID: "uuid-1")
        try await registry.rename(id, to: "Mine")
        try await svc.addClaude(credential: cred("t2"), remoteID: "uuid-1")
        let accounts = await registry.accounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.displayName == "Mine")
        #expect(try store.read(id)?.access.reveal() == "t2")
    }

    @Test func addClaudeWithCredentialDoesNotCallClaudeLogin() async throws {
        let (svc, _, _, _) = try make()
        try await svc.addClaude(credential: cred("t1"), remoteID: "uuid-1")
        #expect(logins.count == 0)
    }

    @Test func removeDeletesStoredItemForAnyKind() async throws {
        let (svc, store, registry, _) = try make()
        let id = AccountID(kind: .codex, remoteID: "acct-1")
        try store.write(cred("c", kind: .codex), for: id, label: "t")
        try await registry.upsert(AccountEntry(id: id, kind: .codex, displayName: "Codex", remoteLogin: nil, order: 0, addedAt: Date(), status: "ok"))
        try await svc.remove(id)
        #expect(try store.read(id) == nil)
    }

    @Test func removeDeletesKeychainSnapshotAndBackoff() async throws {
        let shared = SharedAccountState.inDirectory(dir.appendingPathComponent("group"))
        let mem = InMemoryCredentialStore()
        let (svc, _, registry, _) = try make(store: mem, shared: shared)
        let id = try await svc.addClaude(credential: cred("t1"), remoteID: "uuid-1")
        try shared.cache.write(UsageSnapshot(accountID: id, fetchedAt: Date(), meters: []))
        try shared.backoff.setNextAllowedFetch(Date().addingTimeInterval(60), for: id)
        #expect(FileManager.default.fileExists(atPath: shared.cache.url(for: id).path))
        try await svc.remove(id)
        #expect(try mem.read(id) == nil)
        #expect(!FileManager.default.fileExists(atPath: shared.cache.url(for: id).path))
        #expect(!FileManager.default.fileExists(atPath: shared.backoff.url(for: id).path))
        #expect(await registry.accounts().isEmpty)
    }

    @Test func backoffRemoveMissingIsNoOp() throws {
        let store = SharedBackoffStore(directory: dir)
        try store.remove(AccountID(kind: .claude, remoteID: "none"))
    }
}
