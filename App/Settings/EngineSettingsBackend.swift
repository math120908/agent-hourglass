import Foundation
import UsageCore

/// Live backend. Owns its own `AccountRegistry` view of `accounts.json` and reloads from disk before
/// every write, so it never commits a stale list. Credential work goes through the engine's AccountService.
@MainActor
final class EngineSettingsBackend: SettingsBackend {
    private let engine: UsageEngine
    private let appState: AppState
    private let registry: AccountRegistry?

    init(engine: UsageEngine, appState: AppState) {
        self.engine = engine
        self.appState = appState
        registry = (try? AppSupport.directory()).map { AccountRegistry(directory: $0) }
    }

    func load() async -> (entries: [AccountEntry], menuBar: AccountID?) {
        guard let registry else { return ([], nil) }
        let entries = (try? await registry.load()) ?? []
        return (entries, await registry.menuBarAccountID)
    }

    func rename(_ id: AccountID, to name: String) async throws {
        try await fresh().rename(id, to: name)
    }

    func reorder(_ ids: [AccountID]) async throws {
        try await fresh().reorder(ids)
        await syncOrder()
    }

    func setMenuBarAccount(_ id: AccountID) async throws {
        try await fresh().setMenuBarAccount(id)
    }

    func reauth(_ id: AccountID) async throws {
        guard let service = engine.service else { throw AccountServiceError.unknownAccount }
        try await service.reauth(id)
    }

    func remove(_ id: AccountID) async throws {
        guard let service = engine.service else { throw AccountServiceError.unknownAccount }
        try await service.remove(id)
        appState.snapshots[id] = nil
        appState.statuses[id] = nil
        await syncOrder()
    }

    func setUserInterval(minutes: Int) {
        engine.setUserInterval(minutes: minutes)
    }

    private func fresh() async throws -> AccountRegistry {
        guard let registry else { throw AccountRegistryError.unknownAccount }
        _ = try await registry.load()
        return registry
    }

    /// Popover order follows the registry.
    private func syncOrder() async {
        guard let registry else { return }
        appState.accounts = ((try? await registry.load()) ?? []).map(\.id)
    }
}
