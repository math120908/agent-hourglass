import SwiftUI
import UsageCore

/// Expanded body: Claude hero weekly number, one Instrument `MeterView` per meter, spend, age line.
struct InstrumentMeterGrid: View {
    var kind: ProviderKind
    var meters: [Meter]
    var spend: SpendRow?
    var ageText: String?
    var settings: DisplaySettings
    var now: Date
    var calendar: Calendar
    var onToggleReset: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var options: MeterDisplayOptions { settings.meterOptions(calendar: calendar) }

    /// The weekly meter that actually constrains: the first one with a pace.
    private var hero: MeterDisplay? {
        guard kind == .claude else { return nil }
        return meters.lazy.map { MeterDisplay.make($0, now: now, options: self.options) }.first { $0.paceText != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero { heroView(hero) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(meters.enumerated()), id: \.offset) { _, m in
                    MeterView(meter: m, settings: settings, theme: .instrument, now: now, calendar: calendar, onToggleReset: onToggleReset)
                }
                if let spend { spendRow(spend) }
                if let ageText {
                    Text(ageText)
                        .font(.system(size: 10.5).monospacedDigit())
                        .glassTone()
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 58)
            .padding(.trailing, 14)
        }
        .padding(.bottom, 12)
    }

    private func heroView(_ d: MeterDisplay) -> some View {
        let reset = d.resetText.hasPrefix("Resets ")
            ? "resets " + d.resetText.dropFirst("Resets ".count)
            : d.resetText.lowercased()
        return HStack(alignment: .bottom, spacing: 14) {
            Text(d.percentText)
                .font(.system(size: 34, weight: .semibold).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(textColor(d.severity))
            VStack(alignment: .leading, spacing: 1) {
                Text(d.isRemaining ? "of weekly limit left" : "of weekly limit used")
                Text("\(d.paceText ?? ""), \(reset)")
            }
            .font(.system(size: 11))
            .glassTone()
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func spendRow(_ spend: SpendRow) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Extra usage").font(.system(size: 12))
                if let chip = spend.chip { StatusChipView(text: chip) }
            }
            Spacer(minLength: 10)
            Text(spend.text)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(spend.chip == nil ? AnyShapeStyle(Color.primary) : AnyShapeStyle(dim))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.top, 9)
        GlassMeterBar(
            fraction: spend.fraction,
            paceTick: nil,
            color: spend.chip == nil ? GlassStyle.accent(kind) : Color.primary.opacity(0.45),
            height: 4
        )
        .padding(.top, 5)
    }

    private var dim: Color { scheme == .dark ? .white.opacity(0.90) : .secondary }

    /// Light: the Glass hue. Dark: a lifted variant that keeps >= 4.5:1 on the material.
    private func textColor(_ s: Meter.Severity) -> Color {
        guard scheme == .dark else { return GlassStyle.color(s, kind) }
        return GlassStyle.darkAccent(s, kind)
    }
}
