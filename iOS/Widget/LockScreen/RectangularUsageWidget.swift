import SwiftUI
import UsageCore
import WidgetKit

/// Lock Screen rectangular: account header with age, then up to 3 meter rows.
struct RectangularUsageWidget: Widget {
    static let kind = "RectangularUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectAccountMetersIntent.self, provider: UsageTimelineProvider()) { entry in
            RectangularUsageEntryView(entry: entry)
        }
        .configurationDisplayName("Meters")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Pure content for one rectangular entry. Staleness comes from `entry.date`, never from `entry.status` alone.
struct RectangularUsageContent: Equatable {
    var kind: ProviderKind
    var name: String
    var ageText: String
    var freshness: WidgetFreshness.Freshness
    var rows: [WidgetMeterRow]

    /// The reset line fits only with a single row.
    var showReset: Bool { rows.count == 1 }
    /// A failed account keeps its last number, dimmed, next to its age.
    var isDimmed: Bool { WidgetFreshness.isDimmed(freshness) }

    static func make(_ entry: UsageEntry, calendar: Calendar = .current, locale: Locale = .current) -> RectangularUsageContent? {
        guard let account = entry.account, let snapshot = entry.snapshot else { return nil }
        let meters = WidgetMeterModel.resolveMeters(entry.meterKeys, in: snapshot, family: .rectangular)
        return RectangularUsageContent(
            kind: account.kind,
            name: account.displayName,
            ageText: WidgetFreshness.ageText(fetchedAt: snapshot.fetchedAt, at: entry.date, calendar: calendar, locale: locale, settings: entry.settings),
            freshness: WidgetFreshness.freshness(fetchedAt: snapshot.fetchedAt, status: entry.status, at: entry.date),
            rows: meters.map { WidgetMeterModel.row($0, at: entry.date, settings: entry.settings, calendar: calendar, locale: locale) }
        )
    }
}

private struct RectangularUsageEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = WidgetRenderStyle(renderingMode, theme: entry.theme, colorScheme: colorScheme)
        RectangularUsageView(entry: entry, style: style)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(entry.account.map { DeepLink.url(for: $0.id) })
    }
}

struct RectangularUsageView: View {
    var entry: UsageEntry
    var style: WidgetRenderStyle
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        if let c = RectangularUsageContent.make(entry, calendar: calendar, locale: locale) {
            content(c)
        } else {
            WidgetEmptyView(family: .rectangular, style: style, reason: entry.account == nil ? .noAccount : .noData)
        }
    }

    private func content(_ c: RectangularUsageContent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                ProviderIcon(kind: c.kind, size: 10)
                Text(c.name).lineLimit(1)
                Spacer(minLength: 2)
                AgeLabel(text: c.ageText, freshness: c.freshness, style: style)
            }
            .font(.system(size: 11, weight: .semibold))
            ForEach(c.rows, id: \.key) { row in
                HStack(spacing: 4) {
                    Text(row.shortLabel)
                        .frame(width: 34, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    WidgetBar(fraction: row.fraction, paceTick: row.paceTick, style: style, severity: row.severity, kind: c.kind, height: 4, squared: entry.theme == .instrument)
                    Text(row.percentText).monospacedDigit().lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .opacity(style.dimmed(row.isDimmed || c.isDimmed))
                if c.showReset {
                    Text(row.resetText)
                        .font(.system(size: 11))
                        .foregroundStyle(style.text(.secondary))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("1 row", as: .accessoryRectangular) {
    RectangularUsageWidget()
} timeline: {
    RectangularPreview.entry(count: 1)
}

#Preview("2 rows", as: .accessoryRectangular) {
    RectangularUsageWidget()
} timeline: {
    RectangularPreview.entry(count: 2)
}

#Preview("3 rows", as: .accessoryRectangular) {
    RectangularUsageWidget()
} timeline: {
    RectangularPreview.entry(count: 3)
}

private enum RectangularPreview {
    static func entry(count: Int) -> UsageEntry {
        let now = Date()
        let id = AccountID(rawValue: "claude:preview")!
        let snapshot = UsageSnapshot(accountID: id, fetchedAt: now.addingTimeInterval(-240), meters: [
            Meter(kind: .session5h, label: "5-hour", percentUsed: 34, resetsAt: now.addingTimeInterval(7800), windowLength: .seconds(18000)),
            Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 61, resetsAt: now.addingTimeInterval(3 * 86400), windowLength: .seconds(604_800)),
            Meter(kind: .weeklyModel, label: "Opus", percentUsed: 12),
        ])
        let keys = ["session5h", "weeklyAll", "weeklyModel:Opus"].prefix(count).compactMap(MeterKey.init(rawValue:))
        let account = AccountEntry(id: id, kind: .claude, displayName: "Max", remoteLogin: nil, order: 0, addedAt: now, status: "ok")
        return UsageEntry(date: now, account: account, snapshot: snapshot, status: .fresh, meterKeys: keys, settings: .default, theme: .glass, relevance: nil)
    }
}
