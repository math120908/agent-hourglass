import Foundation
import Observation
import os
import SwiftUI
import UIKit
import UsageCore
import WidgetKit

/// App-wide state: registry entries, cache-first snapshots, the foreground Poller, and account ops.
@MainActor @Observable
final class AppModel {
    let appState: AppState
    private(set) var entries: [AccountEntry] = []
    let service: AccountService
    var focusedAccount: AccountID?

    private let env: UsageEnvironment
    var http: HTTPClient { env.http }
    private let displayStore: DisplaySettingsStore
    private let now: @Sendable () -> Date
    private let poller: Poller
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "AppModel")
    static let pollFloor: Duration = .seconds(60)

    init(env: UsageEnvironment, displayStore: DisplaySettingsStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.env = env
        self.displayStore = displayStore
        self.now = now
        appState = AppState(now: now)
        let box = WeakBox()
        poller = Poller(clients: [], clock: ContinuousClock(), now: now, floor: Self.pollFloor) { id, outcome in
            await MainActor.run { box.model?.deliver(id, outcome) }
        }
        service = AccountService(
            registry: env.registry,
            store: env.store,
            poller: poller,
            history: NoHistory(),
            claudeLogin: { _, _ in throw AccountServiceError.unknownAccount },
            makeClient: { env.makeClient($0) },
            now: now,
            http: env.http,
            shared: env.shared
        )
        box.model = self
    }

    private final class WeakBox: @unchecked Sendable {
        weak var model: AppModel?
    }

    private static func seconds(_ d: Duration) -> TimeInterval {
        let c = d.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }

    /// Fresh iff the cached snapshot is younger than 2 x the interval.
    static func cachedStatus(fetchedAt: Date, now: Date, interval: Duration) -> AccountStatus {
        now.timeIntervalSince(fetchedAt) < 2 * Self.seconds(interval) ? .fresh : .stale
    }

    /// Reads the registry, seeds snapshots from the shared cache, and registers one client per account.
    func load() async {
        do { entries = try await env.registry.load() } catch {
            Self.log.error("registry load failed error=\(String(describing: type(of: error)), privacy: .public)")
            entries = []
        }
        entries = supported(entries)
        let interval = await poller.interval
        appState.effectiveInterval = interval
        let t = now()
        for e in entries {
            seed(e, interval: interval, at: t)
            if let client = env.makeClient(e.id) { await poller.add(client: client) }
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await withBackgroundTask("foreground-poll") {
                await poller.setForeground(true)
                await poller.setUserInterval(.seconds(displayStore.settings.refreshMinutes * 60))
                appState.effectiveInterval = await poller.interval
                await poller.start()
                await poller.refreshAll(force: false)
            }
        case .background:
            await poller.stop()
            await poller.setForeground(false)
            WidgetCenter.shared.reloadAllTimelines()
        default:
            break
        }
    }

    /// Manual refresh. The Poller floor, client backoff and shared cache still gate each provider.
    func refresh() async {
        await withBackgroundTask("manual-poll") { await poller.refreshAll(force: true) }
    }

    /// Called after `service.addClaude/addCodex` commits a new account.
    func accountAdded(_ id: AccountID) async {
        await reloadEntries()
        if let e = entries.first(where: { $0.id == id }) {
            seed(e, interval: appState.effectiveInterval, at: now())
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func rename(_ id: AccountID, to name: String) async throws {
        try await env.registry.rename(id, to: name)
        await reloadEntries()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reorder(_ ids: [AccountID]) async throws {
        try await env.registry.reorder(ids)
        await reloadEntries()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Deletes the Keychain item, snapshot, backoff and registry entry, then drops the card.
    func remove(_ id: AccountID) async throws {
        entries.removeAll { $0.id == id }
        dropState(id)
        if focusedAccount == id { focusedAccount = nil }
        do {
            try await service.remove(id)
        } catch {
            // The registry is the truth: a failed delete must not leave the card hidden.
            await reloadEntries()
            let t = now()
            for e in entries { seed(e, interval: appState.effectiveInterval, at: t) }
            throw error
        }
        try env.shared.cache.remove(id)
        await poller.remove(client: id)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setRefreshMinutes(_ m: Int) async {
        displayStore.settings.refreshMinutes = m
        await poller.setUserInterval(.seconds(displayStore.settings.refreshMinutes * 60))
        appState.effectiveInterval = await poller.interval
    }

    func handle(url: URL) {
        guard let id = DeepLink.accountID(from: url), entries.contains(where: { $0.id == id }) else { return }
        focusedAccount = id
    }

    func diagnosticsReport() -> String {
        let accounts = entries.map { e in
            Diagnostics.Account(
                id: e.id,
                kind: e.kind,
                status: appState.statuses[e.id] ?? .noData,
                snapshot: appState.snapshots[e.id]
            )
        }
        return Diagnostics.report(
            app: "\(BuildInfo.version) (\(BuildInfo.build), \(BuildInfo.commit))",
            accounts: accounts,
            isOffline: appState.isOffline,
            interval: appState.effectiveInterval,
            now: now()
        )
    }

    /// Poller result sink. A result for an account no longer in `entries` (removed while its fetch
    /// was in flight) is dropped, and the snapshot the client just wrote is deleted again.
    func deliver(_ id: AccountID, _ outcome: FetchOutcome) {
        guard entries.contains(where: { $0.id == id }) else {
            try? env.shared.cache.remove(id)
            return
        }
        appState.apply(id, outcome)
    }

    // MARK: - private

    private func seed(_ e: AccountEntry, interval: Duration, at t: Date) {
        if !appState.accounts.contains(e.id) { appState.accounts.append(e.id) }
        appState.names[e.id] = e.displayName
        if let login = e.remoteLogin { appState.logins[e.id] = login }
        guard appState.snapshots[e.id] == nil, let snap = env.shared.cache.read(e.id) else { return }
        appState.snapshots[e.id] = snap
        appState.statuses[e.id] = Self.cachedStatus(fetchedAt: snap.fetchedAt, now: t, interval: interval)
    }

    /// Drops entries this platform cannot poll (iOS v1: Copilot), so they never show or crash.
    private func supported(_ list: [AccountEntry]) -> [AccountEntry] {
        list.filter { env.makeClient($0.id) != nil }
    }

    private func reloadEntries() async {
        entries = supported(await env.registry.accounts())
        let ids = entries.map(\.id)
        appState.accounts = ids
        for e in entries { appState.names[e.id] = e.displayName }
    }

    private func dropState(_ id: AccountID) {
        appState.accounts.removeAll { $0 == id }
        appState.snapshots[id] = nil
        appState.statuses[id] = nil
        appState.lastSuccess[id] = nil
        appState.names[id] = nil
        appState.logins[id] = nil
        appState.setSaveFailed(id, false)
    }

    /// Keeps the app alive until the pass ends, so iOS never suspends it holding the App Group lock.
    private func withBackgroundTask(_ name: String, _ body: () async -> Void) async {
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask(withName: name) {
            app.endBackgroundTask(task)
            task = .invalid
        }
        await body()
        if task != .invalid { app.endBackgroundTask(task) }
    }
}

#if DEBUG
extension AppModel {
    /// Snapshot/preview model: fixture entries and state, backed by a throwaway temp environment.
    static func preview() -> AppModel {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString)")
        let env = try! UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.preview", accessGroup: AppGroup.keychainAccessGroup)
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)")!
        let model = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: defaults), now: { [fixed = Fixtures.now] in fixed })
        model.entries = Fixtures.entries
        for (id, s) in Fixtures.appState().statuses { model.appState.statuses[id] = s }
        return model
    }
}
#endif
