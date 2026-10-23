import SwiftUI
import UsageCore
import WidgetKit

struct SmallInstrumentView: View {
    var entry: UsageEntry
    var style: WidgetRenderStyle

    var body: some View {
        SmallWidgetFrame(entry: entry, style: style) { account, c in
            VStack(alignment: .leading, spacing: 6) {
                if let first = c.rows.first {
                    HStack(spacing: 8) {
                        WidgetRing(fraction: first.fraction, paceTick: first.paceTick, centerText: first.percentText, style: style, severity: first.severity, kind: account.kind, lineWidth: 7)
                            .frame(width: 76, height: 76)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(first.shortLabel).font(.system(size: 12, weight: .semibold).monospaced())
                            Text(first.resetText).font(.system(size: 11)).foregroundStyle(style.text(.tertiary)).lineLimit(2)
                        }
                    }
                    .opacity(style.dimmed(first.isDimmed))
                }
                if c.rows.count > 1 {
                    let second = c.rows[1]
                    HStack(spacing: 4) {
                        Text(second.shortLabel).foregroundStyle(style.text(.secondary))
                        Text(second.percentText).monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .opacity(style.dimmed(second.isDimmed))
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
