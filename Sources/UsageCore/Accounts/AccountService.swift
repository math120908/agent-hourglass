import Foundation
import os

public enum AccountServiceError: Error, Equatable {
    case signInInProgress
    case differentAccount
    case unknownAccount
    case missingAccountID
    case reauthUnsupported
}

/// Orchestrates AccountRegistry + CredentialStore + Poller (spec §4, §5).
public actor AccountService {
    /// `(loginHint, expectedRemoteID) -> (credential, remoteID)`. The remote id is the stable account id.
    public typealias ClaudeLogin = @Sendable (String?, String?) async throws -> (Credential, String)
    /// nil for a kind this platform cannot poll (iOS v1: Copilot); the account is then not polled.
    public typealias MakeClient = @Sendable (AccountID) -> AccountClient?

    private let registry: AccountRegistry
    private let store: CredentialStoring
    private let poller: Poller
    private let history: HistoryDeleting
    private let claudeLogin: ClaudeLogin
    private let makeClient: MakeClient
    private let now: @Sendable () -> Date
    private let ghTokens: (any CopilotTokenSource)?
    private let http: HTTPClient
    private let codexAuth: (any CodexLoginSource)?
    private let shared: SharedAccountState?
    private var signingIn = false
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "AccountService")

    public init(
        registry: AccountRegistry,
        store: CredentialStoring,
        poller: Poller,
        history: HistoryDeleting,
        claudeLogin: @escaping ClaudeLogin,
        makeClient: @escaping MakeClient,
        now: @escaping @Sendable () -> Date = { Date() },
        ghTokens: (any CopilotTokenSource)? = nil,
        http: HTTPClient = HTTPClient(),
        codexAuth: (any CodexLoginSource)? = nil,
        shared: SharedAccountState? = nil
    ) {
        self.shared = shared
        self.codexAuth = codexAuth
        self.ghTokens = ghTokens
        self.http = http
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
        try await commitClaude(cred, id: id)
        return id
    }

    /// Adds a Claude account whose credential was obtained elsewhere (iOS paste-code login). No sign-in;
    /// an id already in the registry is a re-auth. Writes Keychain → registry → one fetch.
    @discardableResult
    public func addClaude(credential: Credential, remoteID: String) async throws -> AccountID {
        let id = AccountID(kind: .claude, remoteID: remoteID)
        try await commitClaude(credential, id: id)
        return id
    }

    public static let ghUserURL = URL(string: "https://api.github.com/user")!

    /// Adds a Copilot account borrowing gh's `login`. Stores only the login, never a Keychain item.
    /// The numeric GitHub user id is the stable id, so a renamed login stays the same account.
    @discardableResult
    public func addCopilot(login: String) async throws -> AccountID {
        guard let ghTokens else { throw GhError.missing }
        let token = try await ghTokens.token(for: login)
        var req = URLRequest(url: Self.ghUserURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await http.send(req, bearer: token)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let num = obj["id"] as? NSNumber else { throw ProviderError.schema(keys: []) }
        let id = AccountID(kind: .copilot, remoteID: num.stringValue)
        let accounts = await registry.accounts()
        let existing = accounts.first { $0.id == id }
        try await registry.upsert(AccountEntry(
            id: id,
            kind: .copilot,
            displayName: existing?.displayName ?? login,
            remoteLogin: login,
            order: existing?.order ?? 0,
            addedAt: existing?.addedAt ?? now(),
            status: "ok"
        ))
        if existing != nil { await poller.remove(client: id) }
        if let client = makeClient(id) { await poller.add(client: client) }
        await poller.refreshAll(force: false)
        return id
    }

    /// Adds the Codex CLI's ChatGPT login. Reads auth.json only; no Keychain item, no network for the id.
    @discardableResult
    public func addCodex() async throws -> AccountID {
        guard let codexAuth else { throw CodexAuthError.missing }
        codexAuth.invalidate()
        let accountID = try codexAuth.login().accountID
        let id = AccountID(kind: .codex, remoteID: accountID)
        let existing = await registry.accounts().first { $0.id == id }
        try await registry.upsert(AccountEntry(
            id: id,
            kind: .codex,
            displayName: existing?.displayName ?? "Codex",
            remoteLogin: nil,
            order: existing?.order ?? 0,
            addedAt: existing?.addedAt ?? now(),
            status: "ok"
        ))
        if existing != nil { await poller.remove(client: id) }
        if let client = makeClient(id) { await poller.add(client: client) }
        await poller.refreshAll(force: false)
        return id
    }

    /// Adds a Codex account whose credential came from the device-code login (iOS). The credential's
    /// `remoteAccountID` is the stable id; an id already in the registry is a re-auth.
    @discardableResult
    public func addCodex(credential: Credential) async throws -> AccountID {
        guard credential.kind == .codex, let remote = credential.remoteAccountID, !remote.isEmpty else {
            throw AccountServiceError.missingAccountID
        }
        let id = AccountID(kind: .codex, remoteID: remote)
        try await commit(credential, id: id, kind: .codex, defaultName: { $0 == 1 ? "Codex" : "Codex #\($0)" }, remoteLogin: nil)
        return id
    }

    /// Adds a Google AI account from the loopback PKCE sign-in. The credential's `remoteAccountID` (the
    /// userinfo `sub`) is the stable id; an id already in the registry is a re-auth.
    @discardableResult
    public func addGoogle(credential: Credential) async throws -> AccountID {
        guard credential.kind == .google, let remote = credential.remoteAccountID, !remote.isEmpty else {
            throw AccountServiceError.missingAccountID
        }
        let id = AccountID(kind: .google, remoteID: remote)
        let email = credential.accountEmail.flatMap { $0.isEmpty ? nil : $0 }
        try await commit(credential, id: id, kind: .google, defaultName: { $0 == 1 ? "Google AI" : "Google AI #\($0)" }, autoName: email, remoteLogin: nil)
        return id
    }

    /// Adds a Grok account from the device-code login. `remoteAccountID` (the OIDC `sub`) is the stable id;
    /// an id already in the registry is a re-auth. The login email is the default name.
    @discardableResult
    public func addGrok(credential: Credential) async throws -> AccountID {
        guard credential.kind == .grok, let remote = credential.remoteAccountID, !remote.isEmpty else {
            throw AccountServiceError.missingAccountID
        }
        let id = AccountID(kind: .grok, remoteID: remote)
        let email = credential.accountEmail.flatMap { $0.isEmpty ? nil : $0 }
        try await commit(credential, id: id, kind: .grok, defaultName: { $0 == 1 ? "Grok" : "Grok #\($0)" }, autoName: email, remoteLogin: nil)
        return id
    }

    /// Adds the read-only Claude Code (local) account. Writes only the registry; the first poll reads the Keychain.
    /// `name` is the user name Claude Code reports (Mac: `ClaudeCodeProfile`); nil keeps the old or default name.
    @discardableResult
    public func addClaudeCodeLocal(name: String? = nil) async throws -> AccountID {
        let id = AccountID.claudeCodeLocal
        let existing = await registry.accounts().first { $0.id == id }
        try await registry.upsert(AccountEntry(
            id: id,
            kind: .claude,
            displayName: AccountEntry.resolvedName(existing: existing, auto: name, fallback: "Claude Code"),
            remoteLogin: "Claude Code (local, read-only)",
            order: existing?.order ?? 0,
            addedAt: existing?.addedAt ?? now(),
            status: "ok",
            nameIsCustom: existing?.nameIsCustom ?? false
        ))
        if existing != nil { await poller.remove(client: id) }
        if let client = makeClient(id) { await poller.add(client: client) }
        await poller.refreshAll(force: false)
        return id
    }

    /// "Try again" for Claude Code (local): a fresh client clears a denied state; still read-only.
    private func readdClaudeCodeLocal() async throws {
        await poller.remove(client: .claudeCodeLocal)
        if let client = makeClient(.claudeCodeLocal) { await poller.add(client: client) }
        await poller.refreshAll(force: false)
    }

    /// Re-auths a Claude `id`. A login that resolves to another account is dropped without any write.
    /// Other kinds re-auth by adding the account again (`reauthUnsupported`).
    public func reauth(_ id: AccountID) async throws {
        guard let entry = await registry.accounts().first(where: { $0.id == id }) else { throw AccountServiceError.unknownAccount }
        if id.isClaudeCodeLocal { return try await readdClaudeCodeLocal() }
        guard entry.kind == .claude else { throw AccountServiceError.reauthUnsupported }
        let remote = String(id.rawValue.dropFirst(entry.kind.rawValue.count + 1))
        let (cred, remoteID) = try await signIn(entry.remoteLogin, remote)
        guard AccountID(kind: entry.kind, remoteID: remoteID) == id else { throw AccountServiceError.differentAccount }
        try await commitClaude(cred, id: id)
    }

    /// Deletes every trace of the account: Keychain item (any kind; a missing item is a no-op),
    /// shared snapshot and backoff files, registry entry (promoting the next menu bar account), history.
    public func remove(_ id: AccountID) async throws {
        await poller.remove(client: id)
        // Our own service only; Claude Code's item is never touched.
        if !id.isClaudeCodeLocal {
            do { try store.delete(id) } catch {
                Self.log.error("keychain delete failed kind=\(id.kind?.rawValue ?? "unknown", privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)")
                throw error
            }
        }
        if let shared {
            try shared.cache.remove(id)
            try shared.backoff.remove(id)
        }
        try await registry.remove(id)
        try await history.deleteAccount(id)
    }

    /// Deletes Keychain items under our service that have no registry entry, for every kind except Codex
    /// and Copilot (left alone, as before); an id of unknown kind is kept.
    /// Entries the registry keeps hidden (undecodable) count as known. Skipped entirely when the registry
    /// quarantined a file: its entries are unknown, not absent.
    public func cleanupOrphans() async throws {
        guard await registry.loadedCleanly else {
            Self.log.notice("orphan cleanup skipped: registry quarantined")
            return
        }
        let known = Set(await registry.accounts().map(\.id) + registry.hiddenIDs())
        let owned = { (id: AccountID) in id.kind.map { $0 != .codex && $0 != .copilot } ?? false }
        for id in try store.allAccountIDs() where owned(id) && !known.contains(id) {
            try store.delete(id)
        }
    }

    private func signIn(_ hint: String?, _ expected: String?) async throws -> (Credential, String) {
        guard !signingIn else { throw AccountServiceError.signInInProgress }
        signingIn = true
        defer { signingIn = false }
        return try await claudeLogin(hint, expected)
    }

    private func commitClaude(_ cred: Credential, id: AccountID) async throws {
        let email = cred.accountEmail.flatMap { $0.isEmpty ? nil : $0 }
        try await commit(cred, id: id, kind: .claude, defaultName: { email ?? "Claude #\($0)" }, autoName: email, remoteLogin: nil)
    }

    /// Keychain → registry → poller. Number = position among accounts of `kind`; an existing entry keeps
    /// order/addedAt and a user-renamed displayName; a non-nil `autoName` replaces an un-renamed one;
    /// a non-nil `remoteLogin` overrides the stored one.
    private func commit(
        _ cred: Credential,
        id: AccountID,
        kind: ProviderKind,
        defaultName: (Int) -> String,
        autoName: String? = nil,
        remoteLogin: String?
    ) async throws {
        let accounts = await registry.accounts()
        let existing = accounts.first { $0.id == id }
        let number = existing.map { e in accounts.filter { $0.kind == kind && $0.order <= e.order }.count }
            ?? accounts.filter { $0.kind == kind }.count + 1
        try store.write(cred, for: id, label: Self.keychainLabel(kind: kind, number: number))
        try await registry.upsert(AccountEntry(
            id: id,
            kind: kind,
            displayName: AccountEntry.resolvedName(existing: existing, auto: autoName, fallback: defaultName(number)),
            remoteLogin: remoteLogin ?? existing?.remoteLogin,
            order: existing?.order ?? 0,
            addedAt: existing?.addedAt ?? now(),
            status: "ok",
            nameIsCustom: existing?.nameIsCustom ?? false
        ))
        if existing != nil { await poller.remove(client: id) }
        if let client = makeClient(id) { await poller.add(client: client) }
        await poller.refreshAll(force: false)
    }
}
