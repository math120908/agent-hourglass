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
    /// Instrument theme: square caps instead of capsules.
    var squared: Bool = false

    private var radius: CGFloat { squared ? 0 : height / 2 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius).fill(style.track())
                    .frame(height: height)
                if let fraction {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(style.fill(severity, kind))
                        .frame(width: max(height, geo.size.width * fraction), height: height)
                        .widgetAccentable()
                }
                if let paceTick {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(style.paceTick())
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: geo.size.width * paceTick - 0.75)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
