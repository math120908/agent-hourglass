import SwiftUI

/// Small capsule tag: plan pill (neutral), status chip (tinted).
struct StatusChipView: View {
    var text: String
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        label
            .padding(.horizontal, 5.5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(base).overlay(Capsule().fill(fill)))
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var label: some View {
        let t = Text(text).font(.system(size: 9.5, weight: .medium))
        if let tint {
            t.foregroundStyle(scheme == .dark ? GlassStyle.darkText(tint) : tint)
        } else {
            t.glassTone(.pill)
        }
    }

    /// Dark mode sinks every pill below the card so its text clears WCAG AA.
    private var base: Color { scheme == .dark ? Color.black.opacity(0.28) : .clear }

    private var fill: Color {
        if let tint { return tint.opacity(scheme == .dark ? 0.18 : 0.15) }
        return scheme == .dark ? .clear : Color.primary.opacity(0.08)
    }
}
