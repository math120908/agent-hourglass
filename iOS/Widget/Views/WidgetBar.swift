import SwiftUI
import UsageCore

/// Widget meter bar; geometry follows `GlassMeterBar`. Only the fill is accentable.
struct WidgetBar: View {
    var fraction: Double?
    var paceTick: Double?
    var style: WidgetRenderStyle
    var severity: Meter.Severity
    var kind: ProviderKind
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(style.track())
                if let fraction {
                    Capsule()
                        .fill(style.fill(severity, kind))
                        .frame(width: max(height, geo.size.width * fraction))
                        .widgetAccentable()
                }
                if let paceTick {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(style.text(.secondary).opacity(0.6))
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: geo.size.width * paceTick - 0.75)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
