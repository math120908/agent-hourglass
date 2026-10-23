import AppIntents
import UsageCore

/// Minimal stand-in for Task 2's `MeterKey`: `Meter.Kind` raw value, plus `:<model>` for
/// weeklyModel and `:<seconds>` for window (same scheme as `HistoryWriter.meterKey`).
/// Task 2 replaces this definition.
struct MeterKey: Hashable, Sendable, RawRepresentable {
    let rawValue: String
    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    init(_ m: Meter) {
        switch m.kind {
        case .weeklyModel: rawValue = "\(m.kind.rawValue):\(m.label)"
        case .window: rawValue = "\(m.kind.rawValue):\(m.windowSeconds ?? 0)"
        default: rawValue = m.kind.rawValue
        }
    }
}

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
    static func meters(for account: AccountEntry, snapshot: UsageSnapshot?) -> [MeterEntity] {
        let pairs: [(MeterKey, String)]
        if let snapshot {
            pairs = snapshot.meters.map { (MeterKey($0), $0.label) }
        } else {
            pairs = defaults(for: account.kind)
        }
        return pairs.map { MeterEntity(id: MeterEntity.makeID(account: account.id, key: $0.0), label: $0.1, key: $0.0) }
    }

    /// Rectangular-family defaults with labels, used before any snapshot exists.
    static func defaults(for kind: ProviderKind) -> [(MeterKey, String)] {
        switch kind {
        case .claude: [(MeterKey(rawValue: "session5h")!, "5-hour"), (MeterKey(rawValue: "weeklyAll")!, "Weekly")]
        case .codex: [(MeterKey(rawValue: "window:18000")!, "5-hour"), (MeterKey(rawValue: "window:604800")!, "Weekly")]
        case .copilot: [(MeterKey(rawValue: "copilotPremium")!, "Premium requests")]
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
