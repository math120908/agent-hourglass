import SwiftUI
import UsageCore

struct GlassAccountCard: View {
    var account: PopoverAccount
    var card: CardModel
    @Binding var isExpanded: Bool
    var onSignIn: () -> Void = {}
    var onDiagnostics: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    private var accent: Color { GlassStyle.accent(account.kind) }
    /// Codex teal is too dark for text on the dark card; lift it to >= 4.5:1.
    private func textTint(_ s: Meter.Severity, _ c: Color) -> Color {
        scheme == .dark && s == .normal && account.kind == .codex ? Color(red: 0.72, green: 0.96, blue: 0.93) : c
    }

    private var dimText: Color { scheme == .dark ? .white.opacity(0.90) : .secondary }

    var body: some View {
        VStack(spacing: 0) {
            compactRow
            if let chip = card.statusChip, chip == "Response format changed" {
                // The name keeps the row; the diagnostics chip moves to its own line.
                Button(action: onDiagnostics) { StatusChipView(text: "Format changed", tint: GlassStyle.critical) }
                    .buttonStyle(.plain)
                    .help("Response format changed. Open About to copy diagnostics.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else if let chip = card.statusChip, !Self.fitsInRow(chip) {
                Text(chip)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(scheme == .dark ? GlassStyle.darkText(GlassStyle.critical) : GlassStyle.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .textSelection(.enabled)
            }
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                        Divider().opacity(0.6)
                        meterSection(row)
                    }
                    if let spend = card.spend {
                        Divider().opacity(0.6)
                        spendSection(spend)
                    }
                    if card.rows.isEmpty && card.spend == nil {
                        Divider().opacity(0.6)
                        Text(card.updatedText)
                            .font(.system(size: 11))
                            .glassTone()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                        .blendMode(.softLight)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 0.5)
        .opacity(card.isDimmed ? 0.82 : 1)
    }

    // MARK: Compact row

    private var compactRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 9) {
                glyph
                VStack(alignment: .leading, spacing: 1) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            nameText.fixedSize()
                            if let plan = card.planTag { StatusChipView(text: plan) }
                        }
                        nameText
                    }
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .glassTone()
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                if let chip = card.statusChip, Self.fitsInRow(chip) {
                    statusChip(chip)
                }
                GlassMeterBar(fraction: card.headline?.fraction, paceTick: nil, color: headlineColor, height: 4)
                    .frame(width: 34)
                Text(headlinePercent)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(headlineTextColor)
                    .frame(minWidth: 38, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .glassTone(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Full name wins over the plan tag; the tag drops first when the row is tight.
    private var nameText: some View {
        Text(account.name)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var glyph: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(accent.gradient)
            .frame(width: 20, height: 20)
            .overlay(
                Text(GlassStyle.glyph(account.kind))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    private var subtitle: String {
        if account.kind == .copilot, let reset = card.headline?.resetText { return reset }
        return card.secondary ?? card.updatedText
    }

    private var headlinePercent: String {
        guard let h = card.headline else { return "--" }
        return h.fraction == nil ? "--" : h.percentText
    }

    private var headlineColor: Color {
        GlassStyle.color(card.headline?.severity ?? .normal, account.kind)
    }

    private var headlineTextColor: Color {
        (card.headline?.severity ?? .normal) == .normal ? .primary : headlineColor
    }

    /// Long recovery copy gets its own line under the row so the row never exceeds 340 pt.
    static func fitsInRow(_ chip: String) -> Bool { chip.count <= 14 }

    @ViewBuilder
    private func statusChip(_ text: String) -> some View {
        if text == "Sign in again" {
            Button(action: onSignIn) { StatusChipView(text: "Sign in", tint: GlassStyle.critical) }
                .buttonStyle(.plain)
        } else {
            StatusChipView(text: text, tint: text == "Stale" ? GlassStyle.warning : GlassStyle.critical)
        }
    }

    // MARK: Expanded sections

    private func meterSection(_ row: MeterRow) -> some View {
        let color = GlassStyle.color(row.severity, account.kind)
        let isWeekly = row.paceTick != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(row.label).font(.system(size: 12, weight: .semibold))
                        if isWeekly && account.kind != .codex { StatusChipView(text: "Weekly") }
                    }
                    if row.paceTick == nil && account.kind == .claude {
                        Text("5-hour rolling window")
                            .font(.system(size: 10.5))
                            .glassTone()
                    }
                }
                Spacer()
                Text(percent(row))
                    .font(.system(size: row.fraction == nil ? 13 : 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(row.fraction == nil ? dimText : textTint(row.severity, color))
            }
            if row.fraction != nil {
                GlassMeterBar(fraction: row.fraction, paceTick: row.paceTick, color: color)
            }
            footerLine(left: row.detailText.map { String($0.split(separator: " (≈").first ?? "") } ?? row.resetText, right: rightText(row))
            if let detail = row.detailText, let money = detail.range(of: "(≈ ") {
                let dollars = detail[money.upperBound...].dropLast()
                footerLine(left: "≈ " + dollars, right: remainingText(row))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Copilot premium keeps one decimal (33.7%), as in the mockup.
    private func percent(_ row: MeterRow) -> String {
        guard row.detailText != nil, let f = row.fraction else { return row.percentText }
        return String(format: "%.1f%%", f * 100)
    }

    private func rightText(_ row: MeterRow) -> String {
        if row.detailText != nil { return row.resetText }
        if let pace = row.paceText { return pace }
        return row.paceTick == nil ? card.updatedText.replacingOccurrences(of: "Updated ", with: "Updated ") : ""
    }

    private func remainingText(_ row: MeterRow) -> String {
        guard let f = row.fraction else { return "" }
        return String(format: "%.1f%% remaining", (1 - f) * 100)
    }

    private func footerLine(left: String, right: String) -> some View {
        HStack {
            Text(left).lineLimit(1)
            Spacer(minLength: 6)
            Text(right).lineLimit(1)
        }
        .font(.system(size: 10.5).monospacedDigit())
        .glassTone()
    }

    private func spendSection(_ spend: SpendRow) -> some View {
        let parts = spend.text.split(separator: " / ", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Extra usage").font(.system(size: 12, weight: .semibold))
                    if let chip = spend.chip { StatusChipView(text: chip) }
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(parts.first ?? spend.text)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    if parts.count > 1 {
                        Text(" / " + parts[1])
                            .font(.system(size: 10.5).monospacedDigit())
                            .glassTone()
                    }
                }
                .foregroundStyle(spend.chip == nil ? Color.primary : dimText)
            }
            GlassMeterBar(
                fraction: spend.fraction,
                paceTick: nil,
                color: spend.chip == nil ? accent : Color.secondary.opacity(0.6)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
