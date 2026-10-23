import Foundation
import UsageCore

/// Deterministic accounts for previews, snapshot renders, and tests. iOS v1: Claude and Codex only.
@MainActor
enum Fixtures {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return c
    }

    /// Fri 23 Oct 2026 23:00 Dublin.
    static var weeklyReset: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23))!
    }

    /// The 7-day weekly window is 52% elapsed.
    static var now: Date { weeklyReset.addingTimeInterval(-0.48 * 7 * 86_400) }

    static let snorlax = AccountID(kind: .claude, remoteID: "happy-hippo")
    static let eevee = AccountID(kind: .claude, remoteID: "eevee")
    static let mewtwo = AccountID(kind: .codex, remoteID: "acct-synthetic")

    /// Snapshot-only extras shared by both card catalogs.
    static let jigglypuff = AccountID(kind: .claude, remoteID: "jigglypuff")
    static let ditto = AccountID(kind: .claude, remoteID: "ditto")

    static func claudeExtra(_ id: AccountID, _ name: String, order: Int) -> AccountEntry {
        AccountEntry(id: id, kind: .claude, displayName: name, remoteLogin: nil, order: order, addedAt: now, status: "active")
    }

    /// Jigglypuff reuses Snorlax's usage (and Max plan) under its own id.
    static var jigglypuffSnapshot: UsageSnapshot {
        var s = snapshots()[snorlax]!
        s.accountID = jigglypuff
        return s
    }

    static var entries: [AccountEntry] {
        [
            AccountEntry(id: snorlax, kind: .claude, displayName: "Snorlax", remoteLogin: nil, order: 0, addedAt: now, status: "active"),
            AccountEntry(id: eevee, kind: .claude, displayName: "Eevee", remoteLogin: nil, order: 1, addedAt: now, status: "active"),
            AccountEntry(id: mewtwo, kind: .codex, displayName: "Mewtwo", remoteLogin: nil, order: 2, addedAt: now, status: "active"),
        ]
    }

    /// Keyed by `AccountID` (AccountEntry is not Hashable in UsageCore).
    static func snapshots() -> [AccountID: UsageSnapshot] {
        let fetched = now.addingTimeInterval(-40)
        let week = Duration.seconds(7 * 86_400)
        let session = Duration.seconds(5 * 3600)
        let sessionReset = now.addingTimeInterval(2 * 3600)
        return [
            snorlax: UsageSnapshot(
                accountID: snorlax,
                fetchedAt: fetched,
                plan: "max_20x",
                meters: [
                    Meter(kind: .session5h, label: "Session", percentUsed: 1, windowLength: session),
                    Meter(kind: .weeklyAll, label: "All models", percentUsed: 39, resetsAt: weeklyReset, windowLength: week),
                    Meter(kind: .weeklyModel, label: "Fable", percentUsed: 21, resetsAt: weeklyReset, windowLength: week),
                ]
            ),
            eevee: UsageSnapshot(
                accountID: eevee,
                fetchedAt: fetched,
                plan: "pro",
                meters: [
                    Meter(kind: .session5h, label: "Session", percentUsed: 82, resetsAt: sessionReset, windowLength: session, severity: .warning),
                    Meter(kind: .weeklyAll, label: "All models", percentUsed: 91, resetsAt: weeklyReset, windowLength: week, severity: .critical),
                ]
            ),
            mewtwo: UsageSnapshot(
                accountID: mewtwo,
                fetchedAt: fetched,
                plan: "go",
                meters: [
                    Meter(
                        kind: .window,
                        label: Meter.windowLabel(seconds: 2_592_000),
                        percentUsed: 12,
                        resetsAt: now.addingTimeInterval(1_296_000),
                        windowLength: .seconds(2_592_000)
                    ),
                ]
            ),
        ]
    }

    /// App state with every fixture account loaded; `statuses` overrides the default `.fresh`.
    static func appState(statuses: [AccountID: AccountStatus] = [:]) -> AppState {
        let fixedNow = now
        let state = AppState(now: { fixedNow })
        for (id, snap) in snapshots() { state.snapshots[id] = snap }
        for e in entries {
            state.accounts.append(e.id)
            state.names[e.id] = e.displayName
            state.statuses[e.id] = statuses[e.id] ?? .fresh
            state.lastSuccess[e.id] = fixedNow.addingTimeInterval(-40)
        }
        return state
    }
}
