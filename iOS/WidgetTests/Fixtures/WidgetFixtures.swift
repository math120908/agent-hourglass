import Foundation
import UsageCore

enum WidgetFixtures {
    static let now = ISO8601DateFormatter().date(from: "2026-10-23T14:20:00Z")!
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return c
    }()
    static let locale = Locale(identifier: "en_US")
    /// Render-matrix locale: 24 h by default, so the 12 h settings variant differs from its base.
    static let renderLocale = Locale(identifier: "en_GB")

    static let claudeMax = UsageSnapshot(accountID: AccountID(rawValue: "claude:max")!, fetchedAt: now, meters: [
        Meter(kind: .session5h, label: "5-hour", percentUsed: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60), windowLength: .seconds(18000)),
        // Fri 23:59 Dublin (UTC+1) = 22:59Z.
        Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 61, resetsAt: ISO8601DateFormatter().date(from: "2026-10-23T22:59:00Z")!, windowLength: .seconds(604_800)),
        Meter(kind: .weeklyModel, label: "Opus", percentUsed: 12),
    ])

    static let codexPlus = UsageSnapshot(accountID: AccountID(rawValue: "codex:plus")!, fetchedAt: now, meters: [
        Meter(kind: .window, label: "5-hour", percentUsed: 8, resetsAt: now.addingTimeInterval(3600), windowLength: .seconds(18000)),
        Meter(kind: .window, label: "Weekly", percentUsed: 72, resetsAt: now.addingTimeInterval(3 * 86400), windowLength: .seconds(604_800)),
    ])

    static var allMeters: [Meter] { [claudeMax, codexPlus].flatMap(\.meters) }

    // MARK: Render matrix state fixtures

    static let claudeAccount = AccountEntry(id: claudeMax.accountID, kind: .claude, displayName: "Claude Max", remoteLogin: nil, order: 0, addedAt: now, status: "ok")
    static let codexAccount = AccountEntry(id: codexPlus.accountID, kind: .codex, displayName: "Codex Plus", remoteLogin: nil, order: 1, addedAt: now, status: "ok")

    /// Fetched 2 h before `now`.
    static var claudeStale: UsageSnapshot {
        var s = claudeMax
        s.fetchedAt = now.addingTimeInterval(-2 * 3600)
        return s
    }

    /// Fetched 3 h before `now`, for the needs-login render.
    static var claudeNeedsLogin: UsageSnapshot {
        var s = claudeMax
        s.fetchedAt = now.addingTimeInterval(-3 * 3600)
        return s
    }

    /// The 5-hour window reset 1 min before `now`; fetched 6 min ago, before the reset.
    static let claudeAfterReset = UsageSnapshot(accountID: claudeMax.accountID, fetchedAt: now.addingTimeInterval(-6 * 60), meters: [
        Meter(kind: .session5h, label: "5-hour", percentUsed: 97, resetsAt: now.addingTimeInterval(-60), windowLength: .seconds(18000)),
        Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 61, resetsAt: ISO8601DateFormatter().date(from: "2026-10-23T22:59:00Z")!, windowLength: .seconds(604_800)),
    ])

    static func entry(
        _ snapshot: UsageSnapshot?,
        account: AccountEntry? = claudeAccount,
        status: AccountStatus? = .fresh,
        theme: Theme = .glass,
        settings: DisplaySettings = .default
    ) -> UsageEntry {
        UsageEntry(date: now, account: account, snapshot: snapshot, status: status, meterKeys: [], settings: settings, theme: theme, relevance: nil)
    }
}
