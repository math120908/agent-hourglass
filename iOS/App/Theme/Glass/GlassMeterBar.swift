import SwiftUI

/// Rounded track with a filled portion and an optional pace tick.
struct GlassMeterBar: View {
    var fraction: Double?
    var paceTick: Double?
    var color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                if let fraction {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * fraction))
                }
                if let paceTick {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: geo.size.width * paceTick - 0.75)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
