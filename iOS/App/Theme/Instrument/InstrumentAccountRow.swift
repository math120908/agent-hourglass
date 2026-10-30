import SwiftUI
import UsageCore

/// One account in the hairline list: ring gauge, name + plan, subtitle, status chip, chevron.
struct InstrumentAccountRow: View {
    var entry: AccountEntry
    var snapshot: UsageSnapshot?
    var status: AccountStatus
    var settings: DisplaySettings
    var now: Date
    var calendar: Calendar
    @Binding var isExpanded: Bool
    var actions: CardActions

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
    private var options: MeterDisplayOptions { settings.meterOptions(calendar: calendar) }
    private var card: CardModel {
        CardModel.make(snapshot: snapshot, status: status, kind: kind, now: now, calendar: calendar, locale: .current)
    }
    private var meters: [Meter] { MeterDisplay.visibleMeters(snapshot) }

    private var headline: MeterDisplay? {
        let k: Meter.Kind = kind.usesWindowMeters ? .window : .session5h
        return meters.first { $0.kind == k }.map { MeterDisplay.make($0, now: now, options: options) }
    }

    var body: some View {
        let c = card
        VStack(spacing: 0) {
            row(c).opacity(dimOpacity(c))
            if isExpanded {
                InstrumentMeterGrid(
                    kind: kind,
                    meters: meters,
                    spend: c.spend,
                    ageText: snapshot.map { MeterDisplay.ageText(fetchedAt: $0.fetchedAt, now: now, options: options) },
                    settings: settings,
                    now: now,
                    calendar: calendar,
                    onToggleReset: actions.toggleReset
                )
                .opacity(dimOpacity(c))
                .transition(.opacity)
            }
            CardAccessorySlot(kind: kind, now: now, calendar: calendar, horizontalPadding: 14)
        }
    }

    /// Dims stale data; dark mode dims less so the lifted tints keep contrast.
    private func dimOpacity(_ c: CardModel) -> Double { c.isDimmed ? (scheme == .dark ? 0.92 : 0.82) : 1 }

    private func row(_ c: CardModel) -> some View {
        HStack(spacing: 10) {
            RingGauge(fraction: headline?.fraction, label: ringLabel, color: ringColor)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            name.fixedSize()
                            if let plan = c.planTag { StatusChipView(text: plan) }
                        }
                        name
                    }
                    UsagePageSlot(kind: kind)
                }
                Text(subtitle)
                    .font(.system(size: 11).monospacedDigit())
                    .glassTone()
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            statusChip
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .glassTone(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() } }
        .accessibilityAddTraits(.isButton)
        .usagePageLink(kind: kind)
    }

    private var name: some View {
        Text(entry.displayName)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var ringLabel: String {
        guard let f = headline?.fraction else { return "--" }
        return "\(Int((f * 100).rounded()))"
    }

    private var ringColor: Color { GlassStyle.color(headline?.severity ?? .normal, kind) }

    /// "Session 1% | Week 39%" (Claude) or "30d 12% | resets Nov 7" (Codex).
    private var subtitle: String {
        guard let h = headline else {
            return snapshot.map { MeterDisplay.ageText(fetchedAt: $0.fetchedAt, now: now, options: options) } ?? "No data yet"
        }
        if kind.usesWindowMeters {
            let reset = h.resetText.hasPrefix("Resets ") ? "resets " + h.resetText.dropFirst(7) : h.resetText
            let second = meters.dropFirst().first.map { MeterDisplay.make($0, now: now, options: options) }
            return "\(h.label) \(h.percentText) | " + (second.map { "\($0.label) \($0.percentText)" } ?? reset)
        }
        let week = meters.first { $0.kind == .weeklyAll }
            .map { " | Week " + MeterDisplay.make($0, now: now, options: options).percentText } ?? ""
        return "Session \(h.percentText)" + week
    }

    @ViewBuilder
    private var statusChip: some View {
        switch StatusAction.make(status) {
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
}
