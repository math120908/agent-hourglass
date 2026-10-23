import SwiftUI

/// Clock glyph plus age. Stale or failed: critical color in full color, exclamation glyph otherwise.
struct AgeLabel: View {
    var text: String
    var freshness: WidgetFreshness.Freshness
    var style: WidgetRenderStyle

    private var isProblem: Bool {
        switch freshness {
        case .stale, .failed: true
        case .fresh, .noData: false
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isProblem && !style.isFullColor ? "exclamationmark.circle" : "clock")
            Text(text).monospacedDigit()
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(isProblem && style.isFullColor ? GlassStyle.critical : style.text(.tertiary))
        .lineLimit(1)
    }
}
