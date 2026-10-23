import SwiftUI
import UsageCore
import WidgetKit

/// Lock Screen ring for the first configured meter.
struct CircularUsageWidget: Widget {
    static let kind = "CircularUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectAccountMetersIntent.self, provider: UsageTimelineProvider()) { entry in
            CircularUsageEntryView(entry: entry)
        }
        .configurationDisplayName("Meter ring")
        .description("One meter as a ring.")
        .supportedFamilies([.accessoryCircular])
    }
}

private struct CircularUsageEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CircularUsageView(entry: entry, style: WidgetRenderStyle(renderingMode, theme: entry.theme, colorScheme: colorScheme))
    }
}

struct CircularUsageView: View {
    var entry: UsageEntry
    var style: WidgetRenderStyle

    struct Content: Equatable, Sendable {
        var row: WidgetMeterRow
        /// Short label when fresh; age text when stale or failed.
        var caption: String
        var isProblem: Bool
        var isDimmed: Bool
    }

    nonisolated static func centerText(_ percentText: String) -> String {
        let digits = percentText.filter(\.isNumber).count
        return digits >= 3 ? percentText.replacingOccurrences(of: "%", with: "") : percentText
    }

    nonisolated static func content(_ e: UsageEntry, calendar: Calendar, locale: Locale) -> Content? {
        guard let s = e.snapshot,
              let meter = WidgetMeterModel.resolveMeters(e.meterKeys, in: s, family: .circular).first
        else { return nil }
        let row = WidgetMeterModel.row(meter, at: e.date, settings: e.settings, calendar: calendar, locale: locale)
        let freshness = WidgetFreshness.freshness(fetchedAt: s.fetchedAt, status: e.status, at: e.date)
        let age = WidgetFreshness.ageText(fetchedAt: s.fetchedAt, at: e.date, calendar: calendar, settings: e.settings)
        let isProblem: Bool
        let isFailed: Bool
        switch freshness {
        case .stale: isProblem = true; isFailed = false
        case .failed: isProblem = true; isFailed = true
        case .fresh, .noData: isProblem = false; isFailed = false
        }
        return Content(row: row, caption: isProblem ? age : row.shortLabel, isProblem: isProblem, isDimmed: row.isDimmed || isFailed)
    }

    private var isGlass: Bool { style.theme == .glass }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let c = Self.content(entry, calendar: .current, locale: .current) {
                ring(c)
            } else {
                WidgetEmptyView(family: .circular, style: style, reason: entry.account == nil ? .noAccount : .noData)
            }
        }
        .widgetURL(entry.account.map { DeepLink.url(for: $0.id) })
        .containerBackground(for: .widget) { Color.clear }
    }

    private func ring(_ c: Content) -> some View {
        ZStack {
            WidgetRing(
                fraction: c.row.fraction,
                paceTick: c.row.paceTick,
                centerText: "",
                style: style,
                severity: c.row.severity,
                kind: entry.snapshot?.accountID.kind ?? .claude,
                lineWidth: isGlass ? 4 : 5
            )
            VStack(spacing: 0) {
                Text(Self.centerText(c.row.percentText))
                    .font(.system(size: 15, weight: isGlass ? .medium : .semibold).monospaced())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(c.caption)
                    .font(.system(size: 8, weight: isGlass ? .regular : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(style.text(.secondary))
            }
            .padding(.horizontal, 7)
        }
        .opacity(style.dimmed(c.isDimmed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.row.label) \(c.row.percentText), \(c.isProblem ? "updated " : "")\(c.caption)")
    }
}

#if DEBUG
private enum CircularPreviewFixtures {
    static let now = Date()
    static let id = AccountID(rawValue: "claude:preview")!
    static let account = AccountEntry(id: id, kind: .claude, displayName: "Claude", remoteLogin: nil, order: 0, addedAt: now, status: "ok")
    static func snapshot(_ pct: Double, age: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(accountID: id, fetchedAt: now.addingTimeInterval(-age), meters: [
            Meter(kind: .session5h, label: "5-hour", percentUsed: pct, resetsAt: now.addingTimeInterval(7200), windowLength: .seconds(18000)),
        ])
    }
    static func entry(_ pct: Double, age: TimeInterval = 60, status: AccountStatus = .fresh, theme: Theme = .glass) -> UsageEntry {
        UsageEntry(date: now, account: account, snapshot: snapshot(pct, age: age), status: status, meterKeys: [], settings: .default, theme: theme, relevance: nil)
    }
}

#Preview(as: .accessoryCircular) {
    CircularUsageWidget()
} timeline: {
    CircularPreviewFixtures.entry(34)
    CircularPreviewFixtures.entry(100, theme: .instrument)
    CircularPreviewFixtures.entry(61, age: 3600)
    CircularPreviewFixtures.entry(20, status: .needsLogin)
}
#endif
