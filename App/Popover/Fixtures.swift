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
        let copilotID = AccountID(kind: .copilot, remoteID: "pikachu-dev")
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
        // Mirrors Tests/UsageCoreTests/Fixtures/codex-go.json (Go plan, 12% of a 30-day window, half elapsed).
        let codexID = AccountID(kind: .codex, remoteID: "acct-synthetic")
        let codex = UsageSnapshot(
            accountID: codexID,
            fetchedAt: fetched,
            plan: "go",
            meters: [
                Meter(kind: .window, label: Meter.windowLabel(seconds: 2_592_000), percentUsed: 12,
                      resetsAt: now.addingTimeInterval(1_296_000), windowLength: .seconds(2_592_000)),
            ]
        )
        // Mirrors Tests/UsageCoreTests/Fixtures/grok-billing-weekly.json (SuperGrok weekly pool, Build/Chat products, $4.20 prepaid).
        let grokID = AccountID(kind: .grok, remoteID: "acct-synthetic")
        let grokReset = now.addingTimeInterval(3 * 86_400)
        let grok = UsageSnapshot(
            accountID: grokID,
            fetchedAt: fetched,
            plan: "SuperGrok",
            meters: [
                Meter(kind: .window, label: "Weekly", percentUsed: 96, resetsAt: grokReset, windowLength: week),
                Meter(kind: .window, label: "Build, weekly", percentUsed: 84, resetsAt: grokReset, windowLength: week, pool: "build"),
                Meter(kind: .window, label: "Chat, weekly", percentUsed: 12, resetsAt: grokReset, windowLength: week, pool: "chat"),
            ],
            spend: Money(usedMinor: 420, limitMinor: nil, currency: "USD", exponent: 2)
        )
        return PopoverContent(
            accounts: [
                PopoverAccount(id: claudeID, name: "Snorlax", kind: .claude, snapshot: claude, status: .fresh),
                PopoverAccount(id: copilotID, name: "pikachu-dev", kind: .copilot, snapshot: copilot, status: .fresh),
                PopoverAccount(id: codexID, name: "Mewtwo", kind: .codex, snapshot: codex, status: .fresh),
                PopoverAccount(id: grokID, name: "Zapdos", kind: .grok, snapshot: grok, status: .fresh),
            ],
            isOffline: false,
            now: now,
            calendar: calendar
        )
    }

    /// Mirrors the mockup timeline (section A): newest first, one credits event, one unconfirmed live entry.
    static func resetEvents(now: Date = Fixtures.now) -> [ResetEvent] {
        let url = URL(string: "https://codex-reset.com")
        func ev(_ id: String, _ day: String, _ kind: ResetEvent.Kind, _ hoursAgo: Double, _ confirmed: Bool, _ summary: String) -> ResetEvent {
            ResetEvent(id: id, day: day, kind: kind, summary: summary, url: url, at: now.addingTimeInterval(-hoursAgo * 3600), confirmed: confirmed)
        }
        return [
            ev("e1", "2026-10-20", .reset, 1.5, false, "Rate limits reset for all Plus & Pro users (live, awaiting confirmation)."),
            ev("e2", "2026-10-19", .reset, 26, true, "Tibo: we reset Codex usage limits for everyone after the outage."),
            ev("e3", "2026-10-17", .reset, 74, true, "Usage limits reset across Codex plans."),
            ev("e4", "2026-10-16", .credits, 98, true, "Bonus credits granted to Pro accounts this week."),
            ev("e5", "2026-10-15", .reset, 122, true, "Weekly limits reset early for all users."),
        ]
    }

    @MainActor static func resetRadar(now: Date = Fixtures.now) -> ResetRadarController {
        ResetRadarController(events: resetEvents(now: now))
    }
}
