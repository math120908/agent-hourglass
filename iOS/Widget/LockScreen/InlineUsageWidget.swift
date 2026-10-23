import SwiftUI
import UsageCore
import WidgetKit

/// Lock Screen inline: one line, `<provider> <percent> | <reset> | <age>`.
struct InlineUsageWidget: Widget {
    static let kind = "InlineUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectAccountMetersIntent.self, provider: UsageTimelineProvider()) { entry in
            InlineUsageView(entry: entry, style: WidgetRenderStyle(mode: .vibrant, theme: entry.theme, colorScheme: .dark))
        }
        .configurationDisplayName("Meter line")
        .supportedFamilies([.accessoryInline])
    }
}

/// Theme has no effect in this family; `style` is accepted for a uniform view signature.
struct InlineUsageView: View {
    var entry: UsageEntry
    var style: WidgetRenderStyle

    var body: some View {
        Label {
            Text(InlineText.text(entry))
        } icon: {
            Image(systemName: "hourglass")
        }
        .widgetURL(entry.account.map { DeepLink.url(for: $0.id) })
        .containerBackground(for: .widget) { Color.clear }
    }
}

enum InlineText {
    static func text(_ entry: UsageEntry, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let kind = entry.account?.kind ?? entry.snapshot?.accountID.kind
        let name = kind.map(shortName)

        guard let snapshot = entry.snapshot,
              let meter = WidgetMeterModel.resolveMeters(entry.meterKeys, in: snapshot, family: .inline).first
        else { return WidgetFreshness.emptyMessage(hasAccount: entry.account != nil) }

        let row = WidgetMeterModel.row(meter, at: entry.date, settings: entry.settings, calendar: calendar, locale: locale)
        let head = [name, row.percentText].compactMap { $0 }.joined(separator: " ")
        let options = entry.settings.meterOptions(calendar: calendar, locale: locale)
        switch WidgetFreshness.freshness(fetchedAt: snapshot.fetchedAt, status: entry.status, at: entry.date) {
        case .fresh:
            return "\(head) | \(row.resetText) | " + MeterDisplay.ageShort(fetchedAt: snapshot.fetchedAt, now: entry.date, options: options)
        case .stale, .noData:
            return "\(head) | " + MeterDisplay.ageText(fetchedAt: snapshot.fetchedAt, now: entry.date, options: options)
        case .failed:
            return "\(head) | Sign in | " + MeterDisplay.ageShort(fetchedAt: snapshot.fetchedAt, now: entry.date, options: options)
        }
    }

    static func shortName(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "Copilot"
        }
    }
}
