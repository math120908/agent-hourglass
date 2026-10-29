import SwiftUI
import UsageCore

/// Mockup A: "Reset radar" row on a Codex card. Collapsed by default; timeline of the newest merged events.
struct ResetRadarRow: View {
    var controller: ResetRadarController
    var now: Date
    var calendar: Calendar
    var horizontalPadding: CGFloat = 12
    @State var isOpen = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var codex: Color { scheme == .dark ? Color(red: 0.72, green: 0.96, blue: 0.93) : GlassStyle.codex }
    private var credit: Color { scheme == .dark ? Color(red: 0.95, green: 0.80, blue: 0.45) : Color(red: 0.62, green: 0.42, blue: 0.04) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(GlassStyle.codex).frame(width: 7, height: 7)
                    Text("Reset radar").font(.system(size: 11.5, weight: .semibold))
                    Spacer(minLength: 4)
                    if let caption = controller.caption(now: now) {
                        Text(caption).font(.system(size: 10.5).monospacedDigit()).glassTone()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .glassTone(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    let entries = controller.entries(calendar: calendar)
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                        entry(e, isLast: i == entries.count - 1)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
            HStack(spacing: 3) {
                Text("Data:")
                Link("codex-reset.com", destination: URL(string: "https://codex-reset.com")!)
            }
            .font(.system(size: 10))
            .glassTone()
            .tint(.secondary)
            .padding(.top, 4)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
    }

    private func entry(_ e: ResetRadarController.Entry, isLast: Bool) -> some View {
        let tint = e.isCredits ? credit : codex
        return HStack(alignment: .top, spacing: 9) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1.5)
                }
                if e.confirmed || e.isCredits {
                    Circle().fill(e.isCredits ? credit : GlassStyle.codex).frame(width: 8, height: 8).padding(.top, 2)
                } else {
                    Circle().strokeBorder(GlassStyle.codex, lineWidth: 1.5).frame(width: 8, height: 8).padding(.top, 2)
                }
            }
            .frame(width: 8)
            Button {
                if let url = e.url { openURL(url) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(e.isCredits ? "Credits" : "Reset")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.16)))
                        Text(e.meta).font(.system(size: 10.5).monospacedDigit()).glassTone()
                    }
                    Text(e.summary)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(e.url == nil)
            .padding(.bottom, isLast ? 2 : 10)
        }
    }
}

extension CardAccessory {
    /// The Codex reset radar, injected into Glass and Instrument cards.
    static let resetRadar = CardAccessory { kind, now, calendar, padding in
        AnyView(ResetRadarSlot(kind: kind, now: now, calendar: calendar, horizontalPadding: padding))
    }
}

/// Appends the radar to a Codex card when the user has it on.
struct ResetRadarSlot: View {
    var kind: ProviderKind
    var now: Date
    var calendar: Calendar
    var horizontalPadding: CGFloat = 12
    @Environment(\.resetRadar) private var controller

    var body: some View {
        if kind == .codex, let controller, controller.settings.show {
            GlassDivider()
            ResetRadarRow(controller: controller, now: now, calendar: calendar, horizontalPadding: horizontalPadding)
        }
    }
}
