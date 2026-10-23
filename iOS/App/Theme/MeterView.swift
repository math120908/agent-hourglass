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
                Text(percent(d))
                    .font(.system(size: d.fraction == nil ? 13 : 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(d.fraction == nil ? dim : glassTint(d.severity, color))
            }
            if d.fraction != nil {
                GlassMeterBar(fraction: d.fraction, paceTick: d.paceTick, color: color)
            }
            footer(left: leftText(d), right: d.detailText != nil ? d.resetText : (d.paceText ?? ""))
            if let money = moneyText(d) {
                footer(left: money, right: remainingText(d), tappable: false)
            }
        }
    }

    private func glassTint(_ s: Meter.Severity, _ c: Color) -> Color {
        scheme == .dark && s == .normal && kind == .codex ? Color(red: 0.72, green: 0.96, blue: 0.93) : c
    }

    // MARK: Instrument

    private func instrument(_ d: MeterDisplay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(instrumentLabel(d)).font(.system(size: 12))
                Spacer(minLength: 10)
                Text(percent(d))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(d.fraction == nil ? dim : instrumentTint(d.severity))
            }
            if d.fraction != nil {
                GlassMeterBar(fraction: d.fraction, paceTick: d.paceTick, color: GlassStyle.color(d.severity, kind), height: 4)
                    .padding(.top, 5)
            }
            footer(left: leftText(d), right: instrumentRight(d))
                .padding(.top, 7)
        }
        .padding(.top, 9)
    }

    private func instrumentLabel(_ d: MeterDisplay) -> String {
        if kind == .claude && d.paceTick == nil && d.paceText == nil && d.label == "Session" { return "Session (5h)" }
        if kind == .codex { return d.label }
        return d.paceText != nil || d.paceTick != nil ? "\(d.label), weekly" : d.label
    }

    private func instrumentRight(_ d: MeterDisplay) -> String {
        if let money = moneyText(d) { return money }
        if d.detailText == nil, kind == .copilot { return "" }
        return d.paceText ?? (d.fraction == 0 ? "idle" : "")
    }

    private func instrumentTint(_ s: Meter.Severity) -> Color {
        guard scheme == .dark else { return GlassStyle.color(s, kind) }
        switch s {
        case .normal:
            switch kind {
            case .claude: return Color(red: 1.0, green: 0.89, blue: 0.81)
            case .copilot: return Color(red: 0.88, green: 0.82, blue: 1.0)
            case .codex: return Color(red: 0.72, green: 0.96, blue: 0.93)
            }
        case .warning: return Color(red: 1.0, green: 0.82, blue: 0.45)
        case .critical: return Color(red: 1.0, green: 0.83, blue: 0.81)
        }
    }

    // MARK: Shared

    private var dim: Color { scheme == .dark ? .white.opacity(0.90) : .secondary }

    /// Copilot premium keeps one decimal (33.7%), as on the Mac.
    private func percent(_ d: MeterDisplay) -> String {
        guard d.detailText != nil, let f = d.fraction else { return d.percentText }
        return String(format: "%.1f%%", f * 100)
    }

    private func leftText(_ d: MeterDisplay) -> String {
        guard let detail = d.detailText else { return d.resetText }
        return String(detail.split(separator: " (≈").first ?? "")
    }

    private func moneyText(_ d: MeterDisplay) -> String? {
        guard let detail = d.detailText, let r = detail.range(of: "(≈ ") else { return nil }
        return "≈ " + detail[r.upperBound...].dropLast()
    }

    private func remainingText(_ d: MeterDisplay) -> String {
        guard let f = d.fraction else { return "" }
        let used = d.isRemaining ? 1 - f : f
        return String(format: "%.1f%% remaining", (1 - used) * 100)
    }

    /// Footer line; the left text toggles the reset style when it is the reset text and a handler exists.
    private func footer(left: String, right: String, tappable: Bool = true) -> some View {
        HStack {
            resetLabel(left, tappable: tappable && left == display.resetText)
            Spacer(minLength: 6)
            Text(right).lineLimit(1)
        }
        .font(.system(size: 10.5).monospacedDigit())
        .glassTone()
    }

    @ViewBuilder
    private func resetLabel(_ text: String, tappable: Bool) -> some View {
        if tappable, let onToggleReset {
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
