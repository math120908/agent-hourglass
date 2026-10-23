import SwiftUI
import UsageCore

/// iOS port of Mac `GlassAccountCard`: compact row, expandable meters, spend, age line.
struct GlassAccountCard: View {
    var entry: AccountEntry
    var snapshot: UsageSnapshot?
    var status: AccountStatus
    var settings: DisplaySettings
    var now: Date
    @Binding var isExpanded: Bool
    var actions: CardActions
    var calendar: Calendar = .current

    @Environment(\.colorScheme) private var scheme

    init(
        entry: AccountEntry,
        snapshot: UsageSnapshot?,
        status: AccountStatus,
        settings: DisplaySettings,
        now: Date,
        isExpanded: Binding<Bool>,
        actions: CardActions,
        calendar: Calendar = .current
    ) {
        self.entry = entry
        self.snapshot = snapshot
        self.status = status
        self.settings = settings
        self.now = now
        self._isExpanded = isExpanded
        self.actions = actions
        self.calendar = calendar
    }

    private var kind: ProviderKind { entry.kind }
    private var accent: Color { GlassStyle.accent(kind) }
    private var options: MeterDisplayOptions { settings.meterOptions(calendar: calendar) }
    private var meters: [Meter] { MeterDisplay.visibleMeters(snapshot) }
    private var action: StatusAction { StatusAction.make(status) }
    private var dimText: Color { scheme == .dark ? .white.opacity(0.90) : .secondary }

    private var card: CardModel {
        CardModel.make(snapshot: snapshot, status: status, kind: kind, now: now, calendar: calendar, locale: options.locale)
    }

    private var headline: MeterDisplay? {
        let k: Meter.Kind = kind == .codex ? .window : .session5h
        return meters.first { $0.kind == k }.map { MeterDisplay.make($0, now: now, options: options) }
    }

    private var ageText: String {
        guard let snapshot else { return "No data yet" }
        return MeterDisplay.ageText(fetchedAt: snapshot.fetchedAt, now: now, options: options)
    }

    var body: some View {
        let c = card
        VStack(spacing: 0) {
            compactRow(c)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(meters.enumerated()), id: \.offset) { _, meter in
                        GlassDivider()
                        MeterView(
                            meter: meter,
                            settings: settings,
                            theme: .glass,
                            now: now,
                            calendar: calendar,
                            onToggleReset: actions.toggleReset
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    if let spend = c.spend {
                        GlassDivider()
                        spendSection(spend)
                    }
                    GlassDivider()
                    Text(ageText)
                        .font(.system(size: 11).monospacedDigit())
                        .glassTone()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .transition(.opacity)
            }
        }
        .opacity(c.isDimmed && action != .offline ? 0.82 : 1)
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
    }

    // MARK: Compact row

    private func compactRow(_ c: CardModel) -> some View {
        let h = headline
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 9) {
                glyph
                VStack(alignment: .leading, spacing: 1) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            nameText.fixedSize()
                            if let plan = c.planTag { StatusChipView(text: plan) }
                        }
                        nameText
                    }
                    Text(c.secondary ?? ageText)
                        .font(.system(size: 10.5))
                        .glassTone()
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                statusChip
                GlassMeterBar(fraction: h?.fraction, paceTick: nil, color: color(h), height: 4)
                    .frame(width: 34)
                Text(h?.fraction == nil ? "--" : h!.percentText)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle((h?.severity ?? .normal) == .normal ? Color.primary : color(h))
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

    private func color(_ d: MeterDisplay?) -> Color {
        GlassStyle.color(d?.severity ?? .normal, kind)
    }

    private var nameText: some View {
        Text(entry.displayName)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var glyph: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(accent.gradient)
            .frame(width: 20, height: 20)
            .overlay(ProviderIcon(kind: kind, size: 12).foregroundStyle(.white))
    }

    @ViewBuilder
    private var statusChip: some View {
        switch action {
        case .stale:
            StatusChipView(text: "Stale", tint: GlassStyle.warning)
        case .signIn:
            Button(action: actions.signIn) { StatusChipView(text: "Sign in again", tint: GlassStyle.critical) }
                .buttonStyle(.plain)
        case .rateLimited(let at):
            StatusChipView(text: Self.retryText(at, options: options), tint: GlassStyle.critical)
        case .formatChanged:
            Button(action: actions.copyDiagnostics) { StatusChipView(text: "Copy diagnostics", tint: GlassStyle.critical) }
                .buttonStyle(.plain)
        case .none, .offline:
            EmptyView()
        }
    }

    nonisolated static func retryText(_ date: Date, options: MeterDisplayOptions) -> String {
        "Retry " + MeterDisplay.clockText(date, options: options)
    }

    // MARK: Spend

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
