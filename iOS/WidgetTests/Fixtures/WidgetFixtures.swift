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

    static let copilot = UsageSnapshot(accountID: AccountID(rawValue: "copilot:c")!, fetchedAt: now, meters: [
        Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: 91, used: 455, limit: 500),
    ])

    static let copilotNoPremium = UsageSnapshot(accountID: AccountID(rawValue: "copilot:n")!, fetchedAt: now, meters: [
        Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: nil, used: 0, limit: 0),
    ])

    static var allMeters: [Meter] { [claudeMax, codexPlus, copilot, copilotNoPremium].flatMap(\.meters) }
}
