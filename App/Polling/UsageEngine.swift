import AppKit
import os
import UsageCore
import UsageHistory
import UsageCoreMac

/// Wires AccountRegistry → AccountService → Poller → AppState, plus sleep/wake and offline.
@MainActor
final class UsageEngine {
    nonisolated private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Engine")

    private let appState: AppState
    private let poller: Poller
    private let registry: AccountRegistry?
    private let labels = LabelBook()
    /// Shared gh token source: one in-memory token cache for add and polling.
    private var gh = GhTokenSource()
    /// Shared read-only view of ~/.codex/auth.json for add and polling.
    private let codex = CodexAuthSource()
    /// Shared Antigravity OAuth client discovery: at most one probe per launch for add and polling.
    private let googleClient = AntigravityClientDiscovery(oauth: GoogleOAuth(http: HTTPClient()))
    let service: AccountService?
    /// Usage history; nil when the store could not be opened (polling continues without it).
    let history: HistoryStore?
    private var maintenanceTimer: Timer?
    /// Raw-sample window in days, from Settings > History (30 or 90).
    nonisolated static let rawDaysKey = "historyRawDays"
    nonisolated static var rawDays: Int {
        UserDefaults.standard.integer(forKey: rawDaysKey) == 30 ? 30 : 90
    }
    private var pathTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(appState: AppState) {
        self.appState = appState
        let history = Self.openHistory()
        self.history = history
        poller = Poller(
            clients: [],
            clock: ContinuousClock(),
            now: { Date() },
            recorder: history,
            onSaveState: { [appState] id, failed in
                await MainActor.run { appState.setSaveFailed(id, failed) }
            }
        ) { [appState] id, outcome in
            await MainActor.run { appState.apply(id, outcome) }
            Self.log.info("result id=\(id.kind == .codex ? "codex" : String(id.rawValue.prefix(14)), privacy: .public) \(Self.summary(outcome), privacy: .public)")
        }
        LegacyMigration.migrateDefaults(old: UserDefaults.standard.persistentDomain(forName: LegacyMigration.oldID), target: .standard)
        guard let dir = try? AppSupport.directory() else {
            Self.log.error("no app support directory")
            registry = nil
            service = nil
            return
        }
        let registry = AccountRegistry(directory: dir)
        let store = CredentialStore()
        let labels = labels
        let gh = GhTokenSource()
        self.gh = gh
        let codex = codex
        let google = googleClient
        self.registry = registry
        service = AccountService(
            registry: registry,
            store: store,
            poller: poller,
            history: history.map { $0 as any HistoryDeleting } ?? NoHistory(),
            claudeLogin: { hint, expected in
                try await ClaudePKCEFlow().run(
                    loginHint: hint,
                    open: { url in Task { @MainActor in AddAccountModel.open(url) } },
                    expectedRemoteID: expected
                )
            },
            makeClient: { id in
                Self.makeClient(id, store: store, label: labels.label(for: id), gh: gh, codex: codex, google: google, login: labels.login(for: id))
            },
            ghTokens: gh,
            codexAuth: codex
        )
    }

    func start() {
        let poller = poller
        runMaintenance()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runMaintenance() }
        }
        Task { [self] in
            await loadAccounts()
            await poller.start()
        }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Self.log.debug("sleep")
            Task { await poller.sleep() }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Self.log.debug("wake")
            Task { await poller.wake() }
        })
        pathTask = Task { [appState] in
            for await online in PathMonitor.updates() {
                appState.isOffline = !online
                await poller.setOffline(!online)
                Self.log.debug("offline=\(!online, privacy: .public)")
            }
        }
    }

    /// Loads the registry, deletes orphaned Keychain items, and adds one client per account.
    private func loadAccounts() async {
        guard let registry, let service else { return }
        let entries: [AccountEntry]
        do {
            entries = try await registry.load()
        } catch {
            Self.log.error("registry load failed: \(String(describing: type(of: error)), privacy: .public) code=\((error as NSError).code, privacy: .public)")
            entries = []
        }
        let claudeIDs = entries.filter { $0.kind == .claude }.map(\.id)
        let kc = LegacyMigration.migrateKeychain(
            ids: claudeIDs,
            old: CredentialStore(service: LegacyMigration.oldID),
            new: CredentialStore(),
            label: { id in AccountService.keychainLabel(kind: .claude, number: (entries.first { $0.id == id }?.order ?? 0) + 1) },
            defaults: .standard
        )
        if kc.failed > 0 { Self.log.error("keychain migration left \(kc.failed, privacy: .public) account(s) needing sign-in") }
        do {
            try await service.cleanupOrphans()
        } catch {
            Self.log.error("orphan cleanup failed: \(String(describing: type(of: error)), privacy: .public) code=\((error as NSError).code, privacy: .public)")
        }
        labels.reset(entries)
        publish(entries)
        let store = CredentialStore()
        for e in entries {
            await poller.add(client: Self.makeClient(e.id, store: store, label: labels.label(for: e.id), gh: gh, codex: codex, google: googleClient, login: e.remoteLogin))
        }
        Self.log.info("engine accounts=\(entries.count, privacy: .public)")
    }

    /// Adds a Claude account; returns its id and first snapshot (if the first fetch has landed).
    func addClaude(loginHint: String?) async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        labels.reset(await registry.accounts())
        let id = try await service.addClaude(loginHint: loginHint)
        let entries = await registry.accounts()
        labels.reset(entries)
        publish(entries)
        return id
    }

    /// github.com logins known to gh; throws `GhError.missing` when gh is absent.
    func copilotLogins() async throws -> [String] { try await gh.logins() }

    /// Adds a Copilot account borrowing gh's `login` (one GET /user, then one fetch).
    func addCopilot(login: String) async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        labels.pendingLogin = login
        defer { labels.pendingLogin = nil }
        let id = try await service.addCopilot(login: login)
        publish(await registry.accounts())
        return id
    }

    /// Adds the Codex CLI login; throws `CodexAuthError` when auth.json is missing or not ChatGPT mode.
    func addCodex() async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        let id = try await service.addCodex()
        publish(await registry.accounts())
        return id
    }

    /// Adds a Google AI account: loopback PKCE sign-in as the Antigravity client found on this Mac.
    func addGoogle() async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        let credential = try await GoogleSignIn(oauth: GoogleOAuth(http: HTTPClient()), client: googleClient)
            .run(open: { url in await MainActor.run { AddAccountModel.open(url) } })
        let id = try await service.addGoogle(credential: credential)
        publish(await registry.accounts())
        return id
    }

    /// Adds a Grok account from a finished device-code login (`GrokDeviceAuth.poll`).
    func addGrok(credential: Credential) async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        let id = try await service.addGrok(credential: credential)
        publish(await registry.accounts())
        return id
    }

    /// Adds an ElevenLabs account from a finished web sign-in (`ElevenLabsWebLogin`).
    func addElevenLabs(credential: Credential) async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        let id = try await service.addElevenLabs(credential: credential)
        publish(await registry.accounts())
        return id
    }

    /// Adds the read-only Claude Code (local) account. The first poll triggers the Keychain prompt.
    func addClaudeCodeLocal() async throws -> AccountID {
        guard let service, let registry else { throw AccountServiceError.unknownAccount }
        let id = try await service.addClaudeCodeLocal(name: ClaudeCodeProfile.userName())
        publish(await registry.accounts())
        return id
    }

    private func publish(_ entries: [AccountEntry]) {
        appState.accounts = entries.map(\.id)
        appState.names = Dictionary(entries.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        appState.logins = Dictionary(entries.compactMap { e in e.remoteLogin.map { (e.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    func setForeground(_ fg: Bool) {
        let poller = poller
        Task { [appState] in
            await poller.setForeground(fg)
            let interval = await poller.interval
            appState.effectiveInterval = interval
            Self.log.debug("foreground=\(fg, privacy: .public) interval=\(Int(interval.components.seconds), privacy: .public)s")
        }
    }

    /// User refresh interval from Settings; applies while the popover is open.
    func setUserInterval(minutes: Int) {
        let poller = poller
        Task { [appState] in
            await poller.setUserInterval(.seconds(minutes * 60))
            appState.effectiveInterval = await poller.interval
            Self.log.debug("user interval=\(minutes * 60, privacy: .public)s")
        }
    }

    /// Manual refresh: Poller enforces the 60 s floor per account.
    func refresh() {
        let poller = poller
        Task {
            Self.log.debug("manual refresh")
            await poller.refreshAll(force: true)
        }
    }

    /// Opens the history store; on failure logs and returns nil so polling degrades to no history.
    private static func openHistory() -> HistoryStore? {
        do {
            return try HistoryStore(url: HistoryStore.defaultURL())
        } catch {
            log.error("history unavailable: \(String(describing: type(of: error)), privacy: .public) code=\((error as NSError).code, privacy: .public)")
            return nil
        }
    }

    /// Runs on launch and hourly; `runMaintenanceIfDue` decides whether today's pass is due.
    private func runMaintenance() {
        guard let history else { return }
        Task.detached {
            do {
                let ran = try await history.runMaintenanceIfDue(now: Date(), calendar: .current, rawDays: Self.rawDays)
                if ran { Self.log.info("history maintenance ran") }
            } catch {
                Self.log.error("history maintenance failed: \(String(describing: type(of: error)), privacy: .public) code=\((error as NSError).code, privacy: .public)")
            }
        }
    }

    nonisolated private static func makeClient(
        _ id: AccountID,
        store: CredentialStore,
        label: String,
        gh: GhTokenSource,
        codex: CodexAuthSource,
        google: AntigravityClientDiscovery,
        login: String? = nil
    ) -> AccountClient {
        if id.isClaudeCodeLocal {
            return AccountClient(
                id: id,
                provider: ClaudeProvider(),
                http: HTTPClient(),
                store: store,
                clock: ContinuousClock(),
                now: { Date() },
                claudeCode: ClaudeCodeKeychainReader()
            )
        }
        if id.kind == .codex {
            return AccountClient(
                id: id,
                provider: CodexProvider(auth: codex),
                http: HTTPClient(),
                store: store,
                clock: ContinuousClock(),
                now: { Date() }
            )
        }
        if id.kind == .google {
            return AccountClient(
                id: id,
                provider: GoogleProvider(client: google),
                http: HTTPClient(),
                store: store,
                clock: ContinuousClock(),
                now: { Date() }
            )
        }
        if id.kind == .grok {
            return AccountClient(
                id: id,
                provider: GrokProvider(),
                http: HTTPClient(),
                store: store,
                clock: ContinuousClock(),
                now: { Date() }
            )
        }
        if id.kind == .elevenlabs {
            return AccountClient(
                id: id,
                provider: ElevenLabsProvider(),
                http: HTTPClient(),
                store: store,
                clock: ContinuousClock(),
                now: { Date() }
            )
        }
        if id.kind == .copilot {
            return AccountClient(
                id: id,
                provider: CopilotProvider(),
                http: HTTPClient(),
                store: store,
                clock: ContinuousClock(),
                now: { Date() },
                tokenSource: gh,
                login: login
            )
        }
        return AccountClient(
            id: id,
            provider: ClaudeProvider(),
            http: HTTPClient(),
            store: store,
            clock: ContinuousClock(),
            now: { Date() },
            label: label
        )
    }

    nonisolated private static func summary(_ outcome: FetchOutcome) -> String {
        switch outcome {
        case let .success(snap):
            snap.meters.map { "\($0.label)=\($0.percentUsed.map { String(format: "%.0f%%", $0) } ?? "-")" }.joined(separator: " ")
        case let .failure(status):
            "failure \(status)"
        }
    }
}

/// Keychain label per account, numbered by registry order like `AccountService.commit`.
private final class LabelBook: @unchecked Sendable {
    private let lock = NSLock()
    private var labels: [AccountID: String] = [:]
    private var logins: [AccountID: String] = [:]
    private var pending: String?
    private var next = 1

    /// Login for a Copilot add in flight, used before its registry entry is known here.
    var pendingLogin: String? {
        get { lock.withLock { pending } }
        set { lock.withLock { pending = newValue } }
    }

    func login(for id: AccountID) -> String? {
        lock.withLock { logins[id] ?? pending }
    }

    func reset(_ entries: [AccountEntry]) {
        var out: [AccountID: String] = [:]
        var n = 0
        for e in entries where e.kind == .claude {
            n += 1
            out[e.id] = AccountService.keychainLabel(kind: .claude, number: n)
        }
        let gh = Dictionary(entries.compactMap { e in e.remoteLogin.map { (e.id, $0) } }, uniquingKeysWith: { a, _ in a })
        lock.withLock {
            labels = out
            logins = gh
            next = n + 1
        }
    }

    func label(for id: AccountID) -> String {
        lock.withLock { labels[id] ?? AccountService.keychainLabel(kind: .claude, number: next) }
    }
}
