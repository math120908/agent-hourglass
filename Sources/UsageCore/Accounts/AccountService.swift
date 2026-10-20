import Foundation

public enum AccountServiceError: Error, Equatable {
    case signInInProgress
    case differentAccount
    case unknownAccount
}

/// Orchestrates AccountRegistry + CredentialStore + Poller (spec §4, §5).
public actor AccountService {
    /// `(loginHint, expectedRemoteID) -> (credential, remoteID)`. The remote id is the stable account id.
    public typealias ClaudeLogin = @Sendable (String?, String?) async throws -> (Credential, String)
    public typealias MakeClient = @Sendable (AccountID) -> AccountClient

    private let registry: AccountRegistry
    private let store: CredentialStoring
    private let poller: Poller
    private let history: HistoryDeleting
    private let claudeLogin: ClaudeLogin
    private let makeClient: MakeClient
    private let now: @Sendable () -> Date
    private var signingIn = false

    public init(
        registry: AccountRegistry,
        store: CredentialStoring,
        poller: Poller,
        history: HistoryDeleting,
        claudeLogin: @escaping ClaudeLogin,
        makeClient: @escaping MakeClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.registry = registry
        self.store = store
        self.poller = poller
        self.history = history
        self.claudeLogin = claudeLogin
        self.makeClient = makeClient
        self.now = now
    }

    public static func keychainLabel(kind: ProviderKind, number: Int) -> String {
        "Claude Usage – \(kind.rawValue) #\(number)"
    }

    /// Signs in; an id already in the registry is a re-auth. Writes Keychain → registry → one fetch.
    @discardableResult
    public func addClaude(loginHint: String?) async throws -> AccountID {
        let (cred, remoteID) = try await signIn(loginHint, nil)
        let id = AccountID(kind: .claude, remoteID: remoteID)
        try await commit(cred, id: id)
        return id
    }

    /// Re-auths `id`. A login that resolves to another account is dropped without any write.
    public func reauth(_ id: AccountID) async throws {
        guard let entry = await registry.accounts().first(where: { $0.id == id }) else { throw AccountServiceError.unknownAccount }
        let remote = String(id.rawValue.dropFirst(entry.kind.rawValue.count + 1))
        let (cred, remoteID) = try await signIn(entry.remoteLogin, remote)
        guard AccountID(kind: entry.kind, remoteID: remoteID) == id else { throw AccountServiceError.differentAccount }
        try await commit(cred, id: id)
    }

    /// Deletes credential, registry entry (promoting the next menu bar account) and history.
    public func remove(_ id: AccountID) async throws {
        await poller.remove(client: id)
        try store.delete(id)
        try await registry.remove(id)
        try await history.deleteAccount(id)
    }

    /// Deletes Keychain items under our service that have no registry entry.
    public func cleanupOrphans() async throws {
        let known = Set(await registry.accounts().map(\.id))
        for id in try store.allAccountIDs() where !known.contains(id) {
            try store.delete(id)
        }
    }

    private func signIn(_ hint: String?, _ expected: String?) async throws -> (Credential, String) {
        guard !signingIn else { throw AccountServiceError.signInInProgress }
        signingIn = true
        defer { signingIn = false }
        return try await claudeLogin(hint, expected)
    }

    private func commit(_ cred: Credential, id: AccountID) async throws {
        let accounts = await registry.accounts()
        let existing = accounts.first { $0.id == id }
        let number = existing.map { e in accounts.filter { $0.kind == .claude && $0.order <= e.order }.count }
            ?? accounts.filter { $0.kind == .claude }.count + 1
        try store.write(cred, for: id, label: Self.keychainLabel(kind: .claude, number: number))
        try await registry.upsert(AccountEntry(
            id: id,
            kind: .claude,
            displayName: existing?.displayName ?? "Claude #\(number)",
            remoteLogin: existing?.remoteLogin,
            order: existing?.order ?? 0,
            addedAt: existing?.addedAt ?? now(),
            status: "ok"
        ))
        if existing != nil { await poller.remove(client: id) }
        await poller.add(client: makeClient(id))
        await poller.refreshAll(force: false)
    }
}
