import AppKit
import os
import UsageCore

/// Wires accounts → AccountClients → Poller → AppState, plus sleep/wake and offline.
@MainActor
final class UsageEngine {
    nonisolated private static let log = Logger(subsystem: "cc.kuoc.claude-usage", category: "Engine")
    /// Temporary until P3's AccountRegistry: the account usagectl logged in with.
    static let cliService = "cc.kuoc.claude-usage.cli"

    private let appState: AppState
    private let poller: Poller
    private var pathTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(appState: AppState) {
        self.appState = appState
        let (ids, clients) = Self.loadClients()
        appState.accounts = ids
        poller = Poller(clients: clients, clock: ContinuousClock(), now: { Date() }) { [appState] id, outcome in
            await MainActor.run { appState.apply(id, outcome) }
            Self.log.debug("result id=\(id.rawValue.prefix(14), privacy: .public) \(Self.summary(outcome), privacy: .public)")
        }
        Self.log.info("engine accounts=\(clients.count, privacy: .public)")
    }

    func start() {
        let poller = poller
        Task { await poller.start() }
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

    nonisolated private static func summary(_ outcome: FetchOutcome) -> String {
        switch outcome {
        case let .success(snap):
            snap.meters.map { "\($0.label)=\($0.percentUsed.map { String(format: "%.0f%%", $0) } ?? "-")" }.joined(separator: " ")
        case let .failure(status):
            "failure \(status)"
        }
    }

    private static func loadClients() -> ([AccountID], [AccountClient]) {
        guard CommandLine.arguments.contains("--use-cli-account") else { return ([], []) }
        struct AccountsFile: Decodable { var accounts: [String] }
        guard let url = try? AppSupport.directory().appendingPathComponent("usagectl-accounts.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(AccountsFile.self, from: data),
              let raw = file.accounts.first, let id = AccountID(rawValue: raw)
        else {
            log.error("--use-cli-account: no usagectl account")
            return ([], [])
        }
        let client = AccountClient(
            id: id,
            provider: ClaudeProvider(),
            http: HTTPClient(),
            store: CredentialStore(service: cliService),
            clock: ContinuousClock(),
            now: { Date() }
        )
        return ([id], [client])
    }
}
