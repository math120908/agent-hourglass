import AppKit
import os
import UsageCore

/// Wires AccountRegistry → AccountService → Poller → AppState, plus sleep/wake and offline.
@MainActor
final class UsageEngine {
    nonisolated private static let log = Logger(subsystem: "cc.kuoc.claude-usage", category: "Engine")

    private let appState: AppState
    private let poller: Poller
    private let registry: AccountRegistry?
    private let labels = LabelBook()
    let service: AccountService?
    private var pathTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(appState: AppState) {
        self.appState = appState
        poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }) { [appState] id, outcome in
            await MainActor.run { appState.apply(id, outcome) }
            Self.log.debug("result id=\(id.rawValue.prefix(14), privacy: .public) \(Self.summary(outcome), privacy: .public)")
        }
        guard let dir = try? AppSupport.directory() else {
            Self.log.error("no app support directory")
            registry = nil
            service = nil
            return
        }
        let registry = AccountRegistry(directory: dir)
        let store = CredentialStore()
        let labels = labels
        self.registry = registry
        service = AccountService(
            registry: registry,
            store: store,
            poller: poller,
            history: NoHistory(),
            claudeLogin: { hint, expected in
                try await ClaudePKCEFlow().run(
                    loginHint: hint,
                    open: { url in Task { @MainActor in AddAccountModel.open(url) } },
                    expectedRemoteID: expected
                )
            },
            makeClient: { id in Self.makeClient(id, store: store, label: labels.label(for: id)) }
        )
    }

    func start() {
        let poller = poller
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
            Self.log.error("registry load failed: \(String(describing: error), privacy: .public)")
            entries = []
        }
        do {
            try await service.cleanupOrphans()
        } catch {
            Self.log.error("orphan cleanup failed: \(String(describing: error), privacy: .public)")
        }
        labels.reset(entries)
        appState.accounts = entries.map(\.id)
        let store = CredentialStore()
        for e in entries {
            await poller.add(client: Self.makeClient(e.id, store: store, label: labels.label(for: e.id)))
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
        appState.accounts = entries.map(\.id)
        return id
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

    /// Manual refresh: Poller enforces the 60 s floor per account.
    func refresh() {
        let poller = poller
        Task {
            Self.log.debug("manual refresh")
            await poller.refreshAll(force: true)
        }
    }

    nonisolated private static func makeClient(_ id: AccountID, store: CredentialStore, label: String) -> AccountClient {
        AccountClient(
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
    private var next = 1

    func reset(_ entries: [AccountEntry]) {
        var out: [AccountID: String] = [:]
        var n = 0
        for e in entries where e.kind == .claude {
            n += 1
            out[e.id] = AccountService.keychainLabel(kind: .claude, number: n)
        }
        lock.withLock {
            labels = out
            next = n + 1
        }
    }

    func label(for id: AccountID) -> String {
        lock.withLock { labels[id] ?? AccountService.keychainLabel(kind: .claude, number: next) }
    }
}
