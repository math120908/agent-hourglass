import Foundation

/// Entry dates for a widget timeline: dense near `now`, sparser later, plus
/// reset and stale moments so countdowns and stale styling stay correct
/// even when the system skips reloads for hours.
enum TimelinePlan {
    static let reloadAfter: TimeInterval = 900
    static let horizon: TimeInterval = 6 * 3600

    private static let denseStep: TimeInterval = 300
    private static let denseSpan: TimeInterval = 3600
    private static let sparseStep: TimeInterval = 900
    private static let minGap: TimeInterval = 60

    static func entryDates(now: Date, resets: [Date], staleAt: Date?) -> [Date] {
        var offsets: [TimeInterval] = stride(from: 0, through: denseSpan, by: denseStep).map { $0 }
        offsets += stride(from: denseSpan + sparseStep, through: horizon, by: sparseStep).map { $0 }
        var dates = offsets.map { now.addingTimeInterval($0) }

        let end = now.addingTimeInterval(horizon)
        let extras = resets + (staleAt.map { [$0] } ?? [])
        dates += extras.filter { $0 > now && $0 <= end }

        var result: [Date] = []
        for date in dates.sorted() {
            if let last = result.last, date.timeIntervalSince(last) < minGap { continue }
            result.append(date)
        }
        return result
    }

    static func reloadDate(now: Date) -> Date {
        now.addingTimeInterval(reloadAfter)
    }
}
