#if DEBUG
import SwiftUI
import UsageCore

enum CardSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "card-glass-fresh", size: .fitting(width: 402), themes: [.glass]) { _ in
            AnyView(GlassCardStack(items: [GlassCardStack.item(Fixtures.snorlax, .fresh)], expanded: true))
        },
        SnapshotScene(name: "card-glass-collapsed", size: .fitting(width: 402), themes: [.glass]) { _ in
            AnyView(GlassCardStack(items: GlassCardStack.collapsedItems, expanded: false))
        },
        SnapshotScene(name: "card-glass-states", size: .fitting(width: 402), themes: [.glass]) { _ in
            AnyView(GlassCardStack(items: GlassCardStack.stateItems, expanded: false))
        },
    ]
}

@MainActor
private struct GlassCardStack: View {
    struct Item {
        var entry: AccountEntry
        var snapshot: UsageSnapshot?
        var status: AccountStatus
    }

    var items: [Item]
    var expanded: Bool

    static let pikachu = AccountID(kind: .claude, remoteID: "pikachu-dev")
    static let ditto = AccountID(kind: .claude, remoteID: "ditto")

    static func entry(_ id: AccountID, _ name: String) -> AccountEntry {
        AccountEntry(id: id, kind: .claude, displayName: name, remoteLogin: nil, order: 9, addedAt: Fixtures.now, status: "active")
    }

    static func item(_ id: AccountID, _ status: AccountStatus) -> Item {
        let e = Fixtures.entries.first { $0.id == id }!
        return Item(entry: e, snapshot: Fixtures.snapshots()[id], status: status)
    }

    static var pikachuSnapshot: UsageSnapshot {
        var s = Fixtures.snapshots()[Fixtures.snorlax]!
        s.accountID = pikachu
        return s
    }

    static var collapsedItems: [Item] {
        [
            item(Fixtures.snorlax, .fresh),
            item(Fixtures.eevee, .fresh),
            item(Fixtures.mewtwo, .fresh),
            Item(entry: entry(pikachu, "pikachu-dev"), snapshot: pikachuSnapshot, status: .fresh),
        ]
    }

    static var stateItems: [Item] {
        var stale = item(Fixtures.snorlax, .stale)
        stale.snapshot?.fetchedAt = Fixtures.now.addingTimeInterval(-23 * 60)
        return [
            stale,
            item(Fixtures.eevee, .needsLogin),
            item(Fixtures.mewtwo, .rateLimited(retryAt: Fixtures.now.addingTimeInterval(25 * 60))),
            Item(entry: entry(pikachu, "pikachu-dev"), snapshot: pikachuSnapshot, status: .schemaError),
            Item(entry: entry(ditto, "Ditto"), snapshot: nil, status: .noData),
        ]
    }

    var body: some View {
        var settings = DisplaySettings.default
        settings.hour24 = .on
        return VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                GlassAccountCard(
                    entry: item.entry,
                    snapshot: item.snapshot,
                    status: item.status,
                    settings: settings,
                    now: Fixtures.now,
                    isExpanded: .constant(expanded),
                    actions: CardActions(),
                    calendar: Fixtures.calendar
                )
            }
        }
        .padding(16)
    }
}
#endif
