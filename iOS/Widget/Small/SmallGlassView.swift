import SwiftUI
import UsageCore
import WidgetKit

struct SmallGlassView: View {
    var entry: UsageEntry
    var style: WidgetRenderStyle

    var body: some View {
        SmallWidgetFrame(entry: entry, style: style) { account, c in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ProviderIcon(kind: account.kind, size: 14)
                    Text(account.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let plan = c.plan {
                        Text(plan).font(.system(size: 9, weight: .semibold)).foregroundStyle(style.text(.secondary)).lineLimit(1)
                    }
                }
                ForEach(c.rows, id: \.key) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.label).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(row.percentText)
                                .monospacedDigit()
                                .foregroundStyle(style.isFullColor ? GlassStyle.color(row.severity, account.kind) : style.text(.secondary))
                        }
                        .font(.system(size: 13, weight: .medium))
                        WidgetBar(fraction: row.fraction, paceTick: row.paceTick, style: style, severity: row.severity, kind: account.kind, height: 5)
                        Text(row.resetText).font(.system(size: 11)).foregroundStyle(style.text(.tertiary)).lineLimit(1)
                    }
                    .opacity(style.dimmed(row.isDimmed))
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    if let age = c.ageText { AgeLabel(text: age, freshness: c.freshness, style: style) }
                }
            }
            .opacity(style.dimmed(c.isDimmed))
        }
    }
}
