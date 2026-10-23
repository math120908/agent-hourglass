import SwiftUI
import UsageCore

/// Widget ring; geometry follows `RingGauge`. Only the progress arc is accentable.
struct WidgetRing: View {
    var fraction: Double?
    var paceTick: Double?
    var centerText: String
    var style: WidgetRenderStyle
    var severity: Meter.Severity
    var kind: ProviderKind
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(style.ringTrack(), lineWidth: lineWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: max(0.01, fraction))
                    .stroke(style.fill(severity, kind), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            if let paceTick {
                GeometryReader { geo in
                    let r = min(geo.size.width, geo.size.height) / 2
                    Rectangle()
                        .fill(style.paceTick())
                        .frame(width: 1.5, height: lineWidth + 4)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2 - r)
                        .rotationEffect(.degrees(360 * paceTick))
                }
            }
            Text(centerText)
                .font(.system(size: centerText.count > 3 ? 11 : 13, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(centerText)
    }
}
