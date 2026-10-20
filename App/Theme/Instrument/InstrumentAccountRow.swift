import SwiftUI
import UsageCore

/// One account in the hairline list: ring gauge, name + plan, subtitle, status chip, chevron.
struct InstrumentAccountRow: View {
    var account: PopoverAccount
    var card: CardModel
    @Binding var isExpanded: Bool
    var onSignIn: () -> Void = {}
    var onDiagnostics: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            row.opacity(dimOpacity)
            if let chip = card.statusChip, chip == "Response format changed" {
                Button(action: onDiagnostics) { StatusChipView(text: "Format changed", tint: GlassStyle.critical) }
                    .buttonStyle(.plain)
                    .help("Response format changed. Open About to copy diagnostics.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 58)
                    .padding(.bottom, 8)
            } else if let chip = card.statusChip, !GlassAccountCard.fitsInRow(chip) {
                Text(Self.unbreakCommands(chip))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(scheme == .dark ? Self.darkCritical : GlassStyle.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 58)
                    .padding(.trailing, 14)
                    .padding(.bottom, 8)
                    .textSelection(.enabled)
            }
            if isExpanded {
                InstrumentMeterGrid(kind: account.kind, card: card)
                    .opacity(dimOpacity)
                    .transition(.opacity)
            }
        }
    }

    /// Dims stale data but not the status text explaining why, so that text keeps its contrast.
    private var dimOpacity: Double { card.isDimmed ? 0.82 : 1 }

    private var row: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                RingGauge(fraction: card.headline?.fraction, label: ringLabel, color: ringColor)
                VStack(alignment: .leading, spacing: 1) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            name.fixedSize()
                            if let plan = card.planTag { StatusChipView(text: plan) }
                        }
                        name
                    }
                    Text(subtitle)
                        .font(.system(size: 11).monospacedDigit())
                        .glassTone()
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                if let chip = card.statusChip, GlassAccountCard.fitsInRow(chip) { statusChip(chip) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .glassTone(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var name: some View {
        Text(account.name)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var ringLabel: String {
        guard let f = card.headline?.fraction else { return "--" }
        return "\(Int((f * 100).rounded()))"
    }

    private var ringColor: Color { GlassStyle.color(card.headline?.severity ?? .normal, account.kind) }

    /// "Session 1% | Week 39%" (Claude) or "Premium 33.7% | resets Nov 1" (Copilot).
    private var subtitle: String {
        guard let h = card.headline else { return card.updatedText }
        if account.kind == .copilot {
            guard let f = h.fraction else { return "Premium \(h.percentText.lowercased())" }
            let reset = h.resetText.hasPrefix("Resets ") ? "resets " + h.resetText.dropFirst(7) : h.resetText
            return String(format: "Premium %.1f%% | ", f * 100) + reset
        }
        let week = card.secondary.map { " | " + $0.replacingOccurrences(of: "Wk ", with: "Week ") } ?? ""
        return "Session \(h.percentText)" + week
    }

    /// Red that keeps >= 4.5:1 on the dark popover material, matching the light-mode hue.
    static let darkCritical = Color(red: 1.0, green: 0.83, blue: 0.81)

    /// Keeps a backticked command on one line by swapping its spaces for no-break spaces.
    static func unbreakCommands(_ text: String) -> String {
        text.split(separator: "`", omittingEmptySubsequences: false).enumerated().map { i, part in
            i % 2 == 1 ? part.replacingOccurrences(of: " ", with: "\u{00A0}") : String(part)
        }.joined(separator: "`")
    }

    @ViewBuilder
    private func statusChip(_ text: String) -> some View {
        if text == "Sign in again" {
            Button(action: onSignIn) { StatusChipView(text: "Sign in", tint: GlassStyle.critical) }
                .buttonStyle(.plain)
        } else {
            StatusChipView(text: text, tint: text == "Stale" ? GlassStyle.warning : GlassStyle.critical)
        }
    }
}
