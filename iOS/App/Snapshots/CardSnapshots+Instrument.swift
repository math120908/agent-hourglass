#if DEBUG
import SwiftUI
import UsageCore

extension CardSnapshots {
    static let instrumentScenes: [SnapshotScene] = [
        SnapshotScene(name: "card-instrument-fresh", size: .fitting(width: 402), themes: [.instrument]) { _ in
            AnyView(InstrumentList(rows: [InstrumentList.Row(entry: Fixtures.entries[0], expanded: true)]))
        },
        SnapshotScene(name: "card-instrument-collapsed", size: .fitting(width: 402), themes: [.instrument]) { _ in
            AnyView(InstrumentList(rows: InstrumentList.collapsedRows))
        },
        SnapshotScene(name: "card-instrument-states", size: .fitting(width: 402), themes: [.instrument]) { _ in
            AnyView(InstrumentList(rows: InstrumentList.stateRows))
        },
    ]
}

@MainActor
private struct InstrumentList: View {
    struct Row {
        var entry: AccountEntry
        var status: AccountStatus = .fresh
        var snapshot: UsageSnapshot?? = nil
        var expanded = false
    }

    var rows: [Row]

    static var collapsedRows: [Row] {
        Fixtures.entries.map { Row(entry: $0) }
            + [Row(entry: Fixtures.claudeExtra(Fixtures.jigglypuff, "Jigglypuff", order: 3), snapshot: .some(Fixtures.jigglypuffSnapshot))]
    }

    static var stateRows: [Row] {
        let e = Fixtures.entries
        let snaps = Fixtures.snapshots()
        var stale = snaps[Fixtures.snorlax]!
        stale.fetchedAt = Fixtures.now.addingTimeInterval(-23 * 60)
        let jiggly = Fixtures.claudeExtra(Fixtures.jigglypuff, "Jigglypuff", order: 3)
        return [
            Row(entry: e[0], status: .stale, snapshot: .some(stale)),
            Row(entry: e[1], status: .needsLogin),
            Row(entry: e[2], status: .rateLimited(retryAt: Fixtures.now.addingTimeInterval(25 * 60))),
            Row(entry: jiggly, status: .schemaError, snapshot: .some(Fixtures.jigglypuffSnapshot)),
            Row(entry: Fixtures.claudeExtra(Fixtures.ditto, "Ditto", order: 4), status: .noData, snapshot: .some(nil)),
        ]
    }

    var body: some View {
        let snaps = Fixtures.snapshots()
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divider().opacity(0.6) }
                InstrumentAccountRow(
                    entry: r.entry,
                    snapshot: r.snapshot ?? snaps[r.entry.id],
                    status: r.status,
                    settings: { var s = DisplaySettings.default; s.hour24 = .on; return s }(),
                    now: Fixtures.now,
                    isExpanded: .constant(r.expanded),
                    actions: CardActions(),
                    calendar: Fixtures.calendar
                )
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(8)
    }
}
#endif
