import SwiftUI

/// Glyph plus age. Fresh: clock, tertiary. Stale: clock, orange. Sign-in needed: sign-in glyph, red.
struct AgeLabel: View {
    var text: String
    var freshness: WidgetFreshness.Freshness
    var style: WidgetRenderStyle

    enum Tone: Equatable, Sendable { case normal, stale, signIn }

    static func tone(_ f: WidgetFreshness.Freshness) -> Tone {
        switch f {
        case .failed: .signIn
        case .stale: .stale
        case .fresh, .noData: .normal
        }
    }

    static func glyph(_ tone: Tone) -> String {
        tone == .signIn ? "person.crop.circle.badge.exclamationmark" : "clock"
    }

    private var color: Color {
        switch Self.tone(freshness) {
        case .normal: style.text(.tertiary)
        case .stale: style.isFullColor ? Color.orange : style.text(.secondary)
        case .signIn: style.isFullColor ? GlassStyle.critical : Color.primary
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: Self.glyph(Self.tone(freshness)))
            Text(text).monospacedDigit()
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}
