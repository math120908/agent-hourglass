import AppKit
import Observation
import os
import UsageCore

/// Account operations the Settings window needs. Provider-agnostic so Copilot rows (P4) slot in.
@MainActor
protocol SettingsBackend: AnyObject {
    func load() async -> (entries: [AccountEntry], menuBar: AccountID?)
    func rename(_ id: AccountID, to name: String) async throws
    func reorder(_ ids: [AccountID]) async throws
    func setMenuBarAccount(_ id: AccountID) async throws
    func reauth(_ id: AccountID) async throws
    func remove(_ id: AccountID) async throws
    func setUserInterval(minutes: Int)
}

@MainActor @Observable
final class SettingsModel {
    static let intervalKey = "refreshIntervalMinutes"
    static let intervals = [1, 2, 5, 10, 15]
    nonisolated private static let log = Logger(subsystem: "cc.kuoc.claude-usage", category: "Settings")

    var entries: [AccountEntry] = []
    /// Read by the status item to pick the icon's account.
    private(set) var menuBarAccount: AccountID?
    var intervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(intervalMinutes, forKey: Self.intervalKey)
            backend?.setUserInterval(minutes: intervalMinutes)
            Self.log.debug("interval=\(self.intervalMinutes * 60, privacy: .public)s")
        }
    }
    var busy: AccountID?
    var error: String?
    let appState: AppState
    @ObservationIgnored private weak var backend: SettingsBackend?

    init(appState: AppState, backend: SettingsBackend?) {
        self.appState = appState
        self.backend = backend
        let stored = UserDefaults.standard.integer(forKey: Self.intervalKey)
        intervalMinutes = Self.intervals.contains(stored) ? stored : 1
    }

    func reload() {
        guard let backend else { return }
        Task {
            let (e, m) = await backend.load()
            entries = e
            menuBarAccount = m
        }
    }

    /// Snapshot rendering only.
    func previewMenuBar(_ id: AccountID?) { menuBarAccount = id }

    func chooseMenuBar(_ id: AccountID) {
        menuBarAccount = id
        run(nil) { try await $0.setMenuBarAccount(id) }
    }

    func rename(_ id: AccountID, to name: String) {
        run(nil) { try await $0.rename(id, to: name) }
    }

    func move(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        let ids = entries.map(\.id)
        run(nil) { try await $0.reorder(ids) }
    }

    func reauth(_ id: AccountID) {
        run(id) { try await $0.reauth(id) }
    }

    func remove(_ id: AccountID) {
        run(id) { try await $0.remove(id) }
    }

    func status(_ id: AccountID) -> AccountStatus { appState.statuses[id] ?? .noData }

    /// Runs `op`, then reloads so the list reflects what was persisted.
    private func run(_ id: AccountID?, _ op: @escaping @MainActor (SettingsBackend) async throws -> Void) {
        guard let backend else { return }
        busy = id
        error = nil
        Task {
            do {
                try await op(backend)
            } catch {
                self.error = Self.message(error)
                Self.log.error("settings op failed: \(String(describing: error), privacy: .public)")
            }
            busy = nil
            reload()
        }
    }

    private static func message(_ e: Error) -> String {
        switch e {
        case AccountServiceError.differentAccount: "That sign-in was a different account. Nothing changed."
        case AccountServiceError.signInInProgress: "Another sign-in is already in progress."
        case AccountRegistryError.emptyName: "Name can't be empty."
        default: "Something went wrong: \(e.localizedDescription)"
        }
    }
}

extension AccountStatus {
    var settingsLabel: String {
        switch self {
        case .fresh: "Up to date"
        case .stale: "Stale"
        case .rateLimited: "Rate limited"
        case .offline: "Offline"
        case .needsLogin: "Needs sign-in"
        case .ghMissing: "gh not found"
        case .ghLoginRemoved: "Not in gh"
        case .schemaError: "Unexpected response"
        case .noData: "No data yet"
        }
    }

    var needsAttention: Bool { !(self == .fresh || self == .noData) }
}
