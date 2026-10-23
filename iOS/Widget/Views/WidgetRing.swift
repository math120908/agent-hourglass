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

    /// Point on the ring for a fraction: 0 at 12 o'clock, clockwise. Fraction is clamped to 0...1.
    nonisolated static func point(on fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = 2 * Double.pi * min(max(fraction, 0), 1) - Double.pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }

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
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let r = min(geo.size.width, geo.size.height) / 2
                    let half = lineWidth / 2 + 2
                    Path { p in
                        p.move(to: Self.point(on: paceTick, center: center, radius: r - half))
                        p.addLine(to: Self.point(on: paceTick, center: center, radius: r + half))
                    }
                    .stroke(style.paceTick(), lineWidth: 1.5)
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
