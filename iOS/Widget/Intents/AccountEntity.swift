import AppIntents
import UsageCore
import os

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    var id: String
    var name: String
    var kind: ProviderKind

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(AccountCatalog.providerName(kind))")
    }
}

enum AccountCatalog {
    static func entities(_ entries: [AccountEntry]) -> [AccountEntity] {
        entries.sorted { $0.order < $1.order }.map { AccountEntity(id: $0.id.rawValue, name: $0.displayName, kind: $0.kind) }
    }

    /// nil id gives the first entry by `order`; an id not present gives nil.
    static func resolve(_ id: String?, in entries: [AccountEntry]) -> AccountEntry? {
        let sorted = entries.sorted { $0.order < $1.order }
        guard let id else { return sorted.first }
        return sorted.first { $0.id.rawValue == id }
    }

    static func providerName(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "GitHub Copilot"
        case .google: "Google AI"
        }
    }

    /// Registry on disk only: no network, no Keychain.
    static func loadEntries() async -> [AccountEntry] {
        do {
            return try await UsageEnvironment.live().registry.load()
        } catch {
            log.error("registry load failed")
            return []
        }
    }

    static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "widget-intent")
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        let all = AccountCatalog.entities(await AccountCatalog.loadEntries())
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        AccountCatalog.entities(await AccountCatalog.loadEntries())
    }

    func defaultResult() async -> AccountEntity? {
        let entries = await AccountCatalog.loadEntries()
        return AccountCatalog.resolve(nil, in: entries).flatMap { AccountCatalog.entities([$0]).first }
    }
}
