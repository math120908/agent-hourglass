import SwiftUI
import UsageCore

/// Expanded body: optional hero weekly number, then a tight label | value grid with thin bars.
struct InstrumentMeterGrid: View {
    var kind: ProviderKind
    var card: CardModel
    @Environment(\.colorScheme) private var scheme

    /// The weekly meter that actually constrains: the first one with a pace.
    private var heroRow: MeterRow? {
        kind == .claude ? card.rows.first { $0.paceText != nil } : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero = heroRow { heroView(hero) }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
                ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in meter(row) }
                if let spend = card.spend { spendRow(spend) }
                if card.rows.isEmpty && card.spend == nil && card.headline != nil {
                    GridRow {
                        Text(card.updatedText).font(.system(size: 11)).glassTone()
                            .gridCellColumns(2)
                            .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 58)
            .padding(.trailing, 14)
        }
        .padding(.bottom, 12)
    }

    private func heroView(_ row: MeterRow) -> some View {
        let reset = row.resetText.hasPrefix("Resets ")
            ? "resets " + row.resetText.dropFirst("Resets ".count)
            : row.resetText.lowercased()
        return HStack(alignment: .bottom, spacing: 14) {
            Text(row.percentText)
                .font(.system(size: 34, weight: .semibold).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(textColor(row.severity))
            VStack(alignment: .leading, spacing: 1) {
                Text("of weekly limit used")
                Text("\(row.paceText ?? ""), \(reset)")
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
    private func meter(_ row: MeterRow) -> some View {
        let c = color(row.severity)
        GridRow(alignment: .firstTextBaseline) {
            Text(label(row)).font(.system(size: 12))
            Text(percent(row))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(row.fraction == nil ? AnyShapeStyle(dim) : AnyShapeStyle(textColor(row.severity)))
                .gridColumnAlignment(.trailing)
        }
        .padding(.top, 9)
        if row.fraction != nil {
            GridRow {
                GlassMeterBar(fraction: row.fraction, paceTick: row.paceTick, color: c, height: 4)
                    .gridCellColumns(2)
                    .padding(.top, 5)
            }
        }
        GridRow {
            HStack {
                Text(leftText(row)).lineLimit(1)
                Spacer(minLength: 6)
                Text(rightText(row)).lineLimit(1)
            }
            .font(.system(size: 10.5).monospacedDigit())
            .glassTone()
            .gridCellColumns(2)
            .padding(.top, 7)
        }
    }

    @ViewBuilder
    private func spendRow(_ spend: SpendRow) -> some View {
        GridRow(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Extra usage").font(.system(size: 12))
                if let chip = spend.chip { StatusChipView(text: chip) }
            }
            Text(spend.text)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(spend.chip == nil ? AnyShapeStyle(Color.primary) : AnyShapeStyle(dim))
                .lineLimit(1)
                .fixedSize()
                .gridColumnAlignment(.trailing)
        }
        .padding(.top, 9)
        GridRow {
            GlassMeterBar(
                fraction: spend.fraction,
                paceTick: nil,
                color: spend.chip == nil ? GlassStyle.accent(kind) : Color.primary.opacity(0.45),
                height: 4
            )
            .gridCellColumns(2)
            .padding(.top, 5)
        }
    }

    private var dim: Color { scheme == .dark ? .white.opacity(0.90) : .secondary }

    private func color(_ s: Meter.Severity) -> Color { GlassStyle.color(s, kind) }

    /// Text tint: the Glass hue in light mode, a lifted variant (>= 4.5:1 on the dark material) in dark mode.
    private func textColor(_ s: Meter.Severity) -> Color {
        guard scheme == .dark else { return color(s) }
        switch s {
        case .normal:
            switch kind {
            case .claude: return Color(red: 1.0, green: 0.89, blue: 0.81)
            case .copilot: return Color(red: 0.88, green: 0.82, blue: 1.0)
            case .codex: return Color(red: 0.72, green: 0.96, blue: 0.93)
            case .google: return Color(red: 0.78, green: 0.86, blue: 1.0)
            }
        case .warning: return Color(red: 1.0, green: 0.82, blue: 0.45)
        case .critical: return InstrumentAccountRow.darkCritical
        }
    }

    private func label(_ row: MeterRow) -> String {
        if kind == .claude && row.paceTick == nil && row.paceText == nil && row.label == "Session" { return "Session (5h)" }
        if kind.usesWindowMeters { return row.label }
        return row.paceText != nil || row.paceTick != nil ? "\(row.label), weekly" : row.label
    }

    private func percent(_ row: MeterRow) -> String {
        guard row.detailText != nil, let f = row.fraction else { return row.percentText }
        return String(format: "%.1f%%", f * 100)
    }

    private func leftText(_ row: MeterRow) -> String {
        guard let d = row.detailText else { return row.resetText }
        return String(d.split(separator: " (≈").first ?? "")
    }

    private func rightText(_ row: MeterRow) -> String {
        if let d = row.detailText, let r = d.range(of: "(≈ ") { return "≈ " + d[r.upperBound...].dropLast() }
        if row.detailText == nil, kind == .copilot { return "" }
        return row.paceText ?? (row.fraction == 0 ? "idle" : "")
    }
}
