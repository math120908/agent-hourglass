#if DEBUG
import SwiftUI

enum MeterSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "harness-smoke", size: .fitting(width: 402)) { _ in
            AnyView(
                VStack(spacing: 16) {
                    GlassMeterBar(fraction: 0.39, paceTick: 0.52, color: .blue)
                    RingGauge(fraction: 0.39, label: "39", color: .blue)
                }
                .padding(24)
            )
        },
    ]
}
#endif
