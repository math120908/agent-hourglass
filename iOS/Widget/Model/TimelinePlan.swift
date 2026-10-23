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
        let grid = offsets.map { now.addingTimeInterval($0) }

        let end = now.addingTimeInterval(horizon)
        func inRange(_ d: Date) -> Bool { d > now && d <= end }
        func clear(_ d: Date, of list: [Date]) -> Bool { !list.contains { abs($0.timeIntervalSince(d)) < minGap } }

        // Priority: staleAt, then resets (earlier wins), then grid. A date within minGap of a
        // higher-priority date is dropped, so a stale value never shows as fresh.
        var kept: [Date] = staleAt.map { inRange($0) ? [$0] : [] } ?? []
        for date in resets.filter(inRange).sorted() where clear(date, of: kept) {
            kept.append(date)
        }
        let gridKept = grid.filter { clear($0, of: kept) }
        var result: [Date] = []
        for date in (kept + gridKept).sorted() {
            if let last = result.last, date.timeIntervalSince(last) < minGap { continue }
            result.append(date)
        }
        return result
    }

    static func reloadDate(now: Date) -> Date {
        now.addingTimeInterval(reloadAfter)
    }
}
