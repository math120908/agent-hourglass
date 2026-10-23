import Foundation
import UsageCore
import WidgetKit

struct UsageEntry: TimelineEntry {
    var date: Date
    var account: AccountEntry?
    var snapshot: UsageSnapshot?
    var status: AccountStatus?
    var meterKeys: [MeterKey]
    var settings: DisplaySettings
    var theme: Theme
    var relevance: TimelineEntryRelevance?
}

struct TimelineInput: Sendable {
    var account: AccountEntry?
    var snapshot: UsageSnapshot?
    var status: AccountStatus?
    var meterKeys: [MeterKey]
    var settings: DisplaySettings
    var theme: Theme
    /// Needed to resolve which meters the entry shows, so only their resets join the plan.
    var family: WidgetFamilyKind
}

/// Pure: input plus `now` to timeline entries.
enum TimelineBuilder {
    static func entries(_ input: TimelineInput, now: Date) -> [UsageEntry] {
        let resets = input.snapshot.map {
            WidgetMeterModel.resolveMeters(input.meterKeys, in: $0, family: input.family).compactMap(\.resetsAt)
        } ?? []
        let staleAt = input.snapshot.map { $0.fetchedAt.addingTimeInterval(WidgetFreshness.staleAfter) }
        return TimelinePlan.entryDates(now: now, resets: resets, staleAt: staleAt).map { entry(input, at: $0) }
    }

    static func entry(_ input: TimelineInput, at date: Date) -> UsageEntry {
        UsageEntry(
            date: date,
            account: input.account,
            snapshot: input.snapshot,
            status: input.status,
            meterKeys: input.meterKeys,
            settings: input.settings,
            theme: input.theme,
            relevance: nil
        )
    }
}
