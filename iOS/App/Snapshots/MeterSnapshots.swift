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
        var kind: ProviderKind
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
        let month = Fixtures.now.addingTimeInterval(20 * 86_400)
        let credits = Meter(
            kind: .window,
            label: "Credits",
            percentUsed: 0.2,
            used: 200,
            limit: 130_539,
            unit: "credits",
            resetsAt: month,
            windowLength: .seconds(30 * 86_400)
        )
        let premium = Meter(
            kind: .copilotPremium,
            label: "Premium requests",
            percentUsed: 33.7,
            used: 84_250,
            limit: 250_000,
            unit: "credits",
            resetsAt: month
        )
        return [
            Item(meter: all, kind: .claude, settings: h24),
            Item(meter: all, kind: .claude, settings: countdown),
            Item(meter: all, kind: .claude, settings: remaining),
            Item(meter: eeveeWeekly, kind: .claude, settings: h24),
            Item(meter: codex, kind: .codex, settings: h24),
            Item(meter: session, kind: .claude, settings: h24),
            Item(meter: credits, kind: .elevenlabs, settings: h24),
            Item(meter: premium, kind: .copilot, settings: h24),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme == .glass ? 0 : 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0, theme == .glass { Divider().opacity(0.6) }
                MeterView(
                    meter: item.meter,
                    kind: item.kind,
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
