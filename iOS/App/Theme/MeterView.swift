import SwiftUI
import UsageCore

/// One meter row in either theme. Glass mirrors Mac `GlassAccountCard.meterSection`;
/// Instrument mirrors Mac `InstrumentMeterGrid.meter`.
struct MeterView: View {
    var meter: Meter
    var settings: DisplaySettings
    var theme: Theme
    var now: Date = Date()
    var calendar: Calendar = .current
    var onToggleReset: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    init(
        meter: Meter,
        settings: DisplaySettings,
        theme: Theme,
        now: Date = Date(),
        calendar: Calendar = .current,
        onToggleReset: (() -> Void)? = nil
    ) {
        self.meter = meter
        self.settings = settings
        self.theme = theme
        self.now = now
        self.calendar = calendar
        self.onToggleReset = onToggleReset
    }

    private var kind: ProviderKind {
        switch meter.kind {
        case .copilotPremium, .copilotChat, .copilotCompletions: .copilot
        case .window: .codex
        default: .claude
        }
    }

    private var display: MeterDisplay {
        MeterDisplay.make(meter, now: now, options: settings.meterOptions(calendar: calendar))
    }

    var body: some View {
        let d = display
        switch theme {
        case .glass: glass(d)
        case .instrument: instrument(d)
        }
    }

    // MARK: Glass

    private func glass(_ d: MeterDisplay) -> some View {
        let color = GlassStyle.color(d.severity, kind)
        let isWeekly = d.paceTick != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(d.label).font(.system(size: 12, weight: .semibold))
                        if isWeekly && kind != .codex { StatusChipView(text: "Weekly") }
                    }
                    if d.paceTick == nil && kind == .claude {
                        Text("5-hour rolling window").font(.system(size: 10.5)).glassTone()
                    }
                }
                Spacer()
                Text(d.percentText)
                    .font(.system(size: d.fraction == nil ? 13 : 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(d.fraction == nil ? dim : glassTint(d.severity, color))
            }
            if d.fraction != nil {
                GlassMeterBar(fraction: d.fraction, paceTick: d.paceTick, color: color)
            }
            footer(left: d.resetText, right: d.paceText ?? "")
        }
    }

    private func glassTint(_ s: Meter.Severity, _ c: Color) -> Color {
        guard scheme == .dark else { return c }
        return GlassStyle.darkAccent(s, kind)
    }

    // MARK: Instrument

    private func instrument(_ d: MeterDisplay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(instrumentLabel(d)).font(.system(size: 12))
                Spacer(minLength: 10)
                Text(d.percentText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(d.fraction == nil ? dim : instrumentTint(d.severity))
            }
            if d.fraction != nil {
                GlassMeterBar(fraction: d.fraction, paceTick: d.paceTick, color: GlassStyle.color(d.severity, kind), height: 4)
                    .padding(.top, 5)
            }
            footer(left: d.resetText, right: d.paceText ?? (d.fraction == 0 ? "idle" : ""))
                .padding(.top, 7)
        }
        .padding(.top, 9)
    }

    private func instrumentLabel(_ d: MeterDisplay) -> String {
        if kind == .claude && d.paceTick == nil && d.paceText == nil && d.label == "Session" { return "Session (5h)" }
        if kind == .codex { return d.label }
        return d.paceText != nil || d.paceTick != nil ? "\(d.label), weekly" : d.label
    }

    private func instrumentTint(_ s: Meter.Severity) -> Color {
        guard scheme == .dark else { return GlassStyle.color(s, kind) }
        return GlassStyle.darkAccent(s, kind)
    }

    // MARK: Shared

    private var dim: Color { scheme == .dark ? .white.opacity(0.90) : .secondary }

    /// Footer line; the reset text toggles the reset style when a handler exists.
    private func footer(left: String, right: String) -> some View {
        HStack {
            resetLabel(left)
            Spacer(minLength: 6)
            Text(right).lineLimit(1)
        }
        .font(.system(size: 10.5).monospacedDigit())
        .glassTone()
    }

    @ViewBuilder
    private func resetLabel(_ text: String) -> some View {
        if let onToggleReset {
            Button(action: onToggleReset) {
                Text(text).lineLimit(1)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -15)
            .accessibilityHint("Switches between clock and countdown")
        } else {
            Text(text).lineLimit(1)
        }
    }
}
