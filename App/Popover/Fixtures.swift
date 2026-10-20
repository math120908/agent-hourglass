import Foundation
import UsageCore

/// Real 2026-10-20 values from the Glass mockup. Used by previews, `--fixture`, and snapshot rendering.
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

    /// Chosen so the 7-day weekly window is 52% elapsed: 39% used reads "13% under pace".
    static var now: Date { weeklyReset.addingTimeInterval(-0.48 * 7 * 86_400) }

    static func content(now: Date = Fixtures.now) -> PopoverContent {
        let fetched = now.addingTimeInterval(-40)
        let claudeID = AccountID(kind: .claude, remoteID: "happy-hippo")
        let copilotID = AccountID(kind: .copilot, remoteID: "ckuo_LinkedIn")
        let week = Duration.seconds(7 * 86_400)
        let claude = UsageSnapshot(
            accountID: claudeID,
            fetchedAt: fetched,
            plan: "max_20x",
            meters: [
                Meter(kind: .session5h, label: "Session", percentUsed: 1, windowLength: .seconds(5 * 3600)),
                Meter(kind: .weeklyAll, label: "All models", percentUsed: 39, resetsAt: weeklyReset, windowLength: week),
                Meter(kind: .weeklyModel, label: "Fable", percentUsed: 21, resetsAt: weeklyReset, windowLength: week),
            ],
            spend: Money(usedMinor: 85, limitMinor: 2000, currency: "EUR", exponent: 2, isEnabled: false, disabledReason: "out_of_credits")
        )
        let copilotReset = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let copilot = UsageSnapshot(
            accountID: copilotID,
            fetchedAt: fetched,
            plan: "enterprise",
            meters: [
                Meter(
                    kind: .copilotPremium,
                    label: "Premium requests",
                    percentUsed: 33.7,
                    used: 84_250,
                    limit: 250_000,
                    resetsAt: copilotReset
                ),
            ]
        )
        return PopoverContent(
            accounts: [
                PopoverAccount(id: claudeID, name: "Happy Hippo", kind: .claude, snapshot: claude, status: .fresh),
                PopoverAccount(id: copilotID, name: "ckuo_LinkedIn", kind: .copilot, snapshot: copilot, status: .fresh),
            ],
            isOffline: false,
            now: now,
            calendar: calendar
        )
    }
}
