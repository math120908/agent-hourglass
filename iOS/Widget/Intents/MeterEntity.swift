import AppIntents
import UsageCore

struct MeterEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meter"
    static let defaultQuery = MeterQuery()

    /// `"<accountID>|<MeterKey.rawValue>"`.
    var id: String
    var label: String
    var key: MeterKey

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }

    static func makeID(account: AccountID, key: MeterKey) -> String { "\(account.rawValue)|\(key.rawValue)" }

    /// Splits on the first `|`; both account ids and keys may contain `:`.
    static func parseID(_ id: String) -> (account: AccountID, key: MeterKey)? {
        guard let bar = id.firstIndex(of: "|"),
              let account = AccountID(rawValue: String(id[..<bar])),
              !account.rawValue.isEmpty,
              let key = MeterKey(rawValue: String(id[id.index(after: bar)...]))
        else { return nil }
        return (account, key)
    }
}

enum MeterCatalog {
    /// Visible meters of the snapshot, else the rectangular-family defaults.
    static func meters(for account: AccountEntry, snapshot: UsageSnapshot?) -> [MeterEntity] {
        let pairs: [(MeterKey, String)]
        if let snapshot {
            pairs = WidgetMeterModel.visibleMeters(snapshot).map { (MeterKey($0), $0.label) }
        } else {
            pairs = WidgetMeterModel.defaultKeys(for: account.kind, family: .rectangular).map { ($0, label(for: $0)) }
        }
        return pairs.map { MeterEntity(id: MeterEntity.makeID(account: account.id, key: $0.0), label: $0.1, key: $0.0) }
    }

    /// Label for a default key before any snapshot exists.
    static func label(for key: MeterKey) -> String {
        let parts = key.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "session5h": return Meter.windowLabel(seconds: 18000)
        case "weeklyAll": return Meter.windowLabel(seconds: 604_800)
        case "copilotPremium": return "Premium requests"
        case "window": return Meter.windowLabel(seconds: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
        default: return parts.count > 1 ? parts[1] : parts[0]
        }
    }
}

struct MeterQuery: EntityQuery {
    @IntentParameterDependency<SelectAccountMetersIntent>(\.$account) var intent

    private func available() async -> [MeterEntity] {
        let entries = await AccountCatalog.loadEntries()
        guard let entry = AccountCatalog.resolve(intent?.account.id, in: entries) else { return [] }
        let snapshot = UsageEnvironment.live().shared.cache.read(entry.id)
        return MeterCatalog.meters(for: entry, snapshot: snapshot)
    }

    func entities(for identifiers: [String]) async throws -> [MeterEntity] {
        // Resolve by id even if the account parameter changed, so saved selections keep labels.
        let entries = await AccountCatalog.loadEntries()
        let cache = UsageEnvironment.live().shared.cache
        return identifiers.compactMap { id in
            guard let parsed = MeterEntity.parseID(id),
                  let entry = entries.first(where: { $0.id == parsed.account }) else { return nil }
            return MeterCatalog.meters(for: entry, snapshot: cache.read(entry.id)).first { $0.id == id }
        }
    }

    func suggestedEntities() async throws -> [MeterEntity] { await available() }
}
