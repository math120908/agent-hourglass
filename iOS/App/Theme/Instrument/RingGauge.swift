import SwiftUI

/// Circular gauge: track, rounded progress arc from 12 o'clock, integer percent in the middle.
struct RingGauge: View {
    var fraction: Double?
    var label: String
    var color: Color
    var size: CGFloat = 34
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: max(0.01, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(label)
                .font(.system(size: label.count > 3 ? 8.5 : 10, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
