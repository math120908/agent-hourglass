import SwiftUI
import UsageCore
import WidgetKit

/// Pure view model for the small widget: rows, freshness and age, derived from the entry date.
struct SmallWidgetContent {
    var rows: [WidgetMeterRow]
    var freshness: WidgetFreshness.Freshness
    var ageText: String?
    var plan: String?

    init(_ entry: UsageEntry, calendar: Calendar = .current, locale: Locale = .current) {
        let snap = entry.snapshot
        rows = snap.map { s in
            WidgetMeterModel.resolveMeters(entry.meterKeys, in: s, family: .small)
                .map { WidgetMeterModel.row($0, at: entry.date, settings: entry.settings, calendar: calendar, locale: locale) }
        } ?? []
        freshness = WidgetFreshness.freshness(fetchedAt: snap?.fetchedAt, status: entry.status, at: entry.date)
        ageText = snap.map { WidgetFreshness.ageText(fetchedAt: $0.fetchedAt, at: entry.date, calendar: calendar, locale: locale, settings: entry.settings) }
        plan = snap?.plan
    }

    var isDimmed: Bool { WidgetFreshness.isDimmed(freshness) }
}

struct SmallUsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SmallUsageWidget", intent: SelectAccountMetersIntent.self, provider: UsageTimelineProvider()) { entry in
            SmallUsageEntryView(entry: entry)
        }
        .configurationDisplayName("Usage")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallUsageEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = WidgetRenderStyle(renderingMode, theme: entry.theme, colorScheme: colorScheme)
        Group {
            switch entry.theme {
            case .glass: SmallGlassView(entry: entry, style: style)
            case .instrument: SmallInstrumentView(entry: entry, style: style)
            }
        }
        .widgetContainerBackground(style: style)
    }
}

/// Shared empty/link handling for both small layouts.
struct SmallWidgetFrame<Content: View>: View {
    var entry: UsageEntry
    var style: WidgetRenderStyle
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    var content: (AccountEntry, SmallWidgetContent) -> Content

    var body: some View {
        if let account = entry.account {
            let c = SmallWidgetContent(entry, calendar: calendar, locale: locale)
            if c.rows.isEmpty, c.freshness == .noData {
                WidgetEmptyView(family: .small, style: style, reason: .noData)
                    .widgetURL(DeepLink.url(for: account.id))
            } else {
                content(account, c)
                    .widgetURL(DeepLink.url(for: account.id))
            }
        } else {
            WidgetEmptyView(family: .small, style: style, reason: .noAccount)
        }
    }
}

#if DEBUG
private enum SmallPreviewData {
    static let now = Date()
    static let account = AccountEntry(id: AccountID(rawValue: "claude:max")!, kind: .claude, displayName: "Claude Max", remoteLogin: nil, order: 0, addedAt: now, status: "ok")
    static let snapshot = UsageSnapshot(accountID: account.id, fetchedAt: now.addingTimeInterval(-300), meters: [
        Meter(kind: .session5h, label: "5-hour", percentUsed: 34, resetsAt: now.addingTimeInterval(7800), windowLength: .seconds(18000)),
        Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 61, resetsAt: now.addingTimeInterval(3 * 86400), windowLength: .seconds(604_800)),
    ])
    static func entry(_ theme: Theme, status: AccountStatus? = .fresh, account: AccountEntry? = account, snapshot: UsageSnapshot? = snapshot) -> UsageEntry {
        UsageEntry(date: now, account: account, snapshot: snapshot, status: status, meterKeys: [], settings: .default, theme: theme, relevance: nil)
    }
}

#Preview("Glass", as: .systemSmall) {
    SmallUsageWidget()
} timeline: {
    SmallPreviewData.entry(.glass)
    SmallPreviewData.entry(.glass, status: .needsLogin)
    SmallPreviewData.entry(.glass, account: nil, snapshot: nil)
}

#Preview("Instrument", as: .systemSmall) {
    SmallUsageWidget()
} timeline: {
    SmallPreviewData.entry(.instrument)
    SmallPreviewData.entry(.instrument, status: .needsLogin)
    SmallPreviewData.entry(.instrument, account: nil, snapshot: nil)
}
#endif
