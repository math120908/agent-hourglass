#if DEBUG
import SwiftUI
import UsageCore

enum MeterSnapshots {
    static let scenes: [SnapshotScene] = [
        SnapshotScene(name: "meter-gallery", size: .fitting(width: 370)) { theme in
            AnyView(MeterGallery(theme: theme))
        },
    ]
}

@MainActor
private struct MeterGallery: View {
    var theme: Theme

    private struct Item {
        var meter: Meter
        var settings: DisplaySettings
    }

    private var items: [Item] {
        let snaps = Fixtures.snapshots()
        let all = snaps[Fixtures.snorlax]!.meters[1]
        let session = snaps[Fixtures.snorlax]!.meters[0]
        let eeveeWeekly = snaps[Fixtures.eevee]!.meters[1]
        let codex = snaps[Fixtures.mewtwo]!.meters[0]
        let base = DisplaySettings.default
        var h24 = base; h24.hour24 = .on
        var countdown = h24; countdown.resetStyle = .countdown
        var remaining = base; remaining.showRemaining = true; remaining.hour24 = .off
        return [
            Item(meter: all, settings: h24),
            Item(meter: all, settings: countdown),
            Item(meter: all, settings: remaining),
            Item(meter: eeveeWeekly, settings: h24),
            Item(meter: codex, settings: h24),
            Item(meter: session, settings: h24),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme == .glass ? 0 : 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0, theme == .glass { Divider().opacity(0.6) }
                MeterView(
                    meter: item.meter,
                    settings: item.settings,
                    theme: theme,
                    now: Fixtures.now,
                    calendar: Fixtures.calendar,
                    onToggleReset: {}
                )
                .padding(.horizontal, theme == .glass ? 12 : 14)
                .padding(.vertical, theme == .glass ? 10 : 0)
            }
        }
        .padding(.bottom, theme == .glass ? 0 : 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(16)
    }
}
#endif
