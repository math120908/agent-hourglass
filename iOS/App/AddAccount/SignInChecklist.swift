import SwiftUI
import UsageCore

/// Where one checklist row stands. Shared by the Claude and Codex add-account sheets.
enum SignInStep: Equatable { case todo, current, done }

/// The add-account sheet skeleton: Cancel, centered provider header, one lead line, the card,
/// then the primary slot. Scrolls only when it must (AX type sizes); otherwise pinned top.
struct SignInSheetLayout<Card: View, Primary: View>: View {
    let kind: ProviderKind
    let title: String
    let lead: String
    @ViewBuilder let card: Card
    @ViewBuilder let primary: Primary

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var markSize: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ProviderIcon(kind: kind, size: markSize)
                        .foregroundStyle(GlassStyle.accent(kind))
                        .accessibilityHidden(true)
                    Text(title).font(.headline)
                }
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
                Text(lead)
                    .font(.subheadline)
                    .foregroundStyle(SheetTone.secondary(scheme, glass: theme == .glass))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                card.sheetCard().padding(.top, 24)
                primary.padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { AppBackdrop().ignoresSafeArea() }
        .tint(GlassStyle.fill(kind))
        // Cancel stays in every state so the layout never jumps; the readable accent variant
        // (the stock accent is ~3:1 on the light toolbar pill).
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.tint(SheetTone.accentText(kind, scheme))
            }
        }
    }
}

/// One checklist row: indicator, label, optional control. A `VStack` at AX sizes.
struct SignInStepRow<Control: View>: View {
    let number: Int
    let label: String
    let step: SignInStep
    let kind: ProviderKind
    var combine = true
    @ViewBuilder let control: Control

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let glass = theme == .glass
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            StepIndicator(number: number, step: step, kind: kind, glass: glass, scheme: scheme)
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    switch step {
                    case .todo: Text(label).font(.body).foregroundStyle(SheetTone.secondary(scheme, glass: glass))
                    case .current: Text(label).font(.body.weight(.semibold))
                    case .done: Text(label).font(.body)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28)
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minHeight: 56)
        .accessibilityElement(children: combine ? .combine : .contain)
    }
}

/// Row separator: the Glass divider, or a hairline on Instrument.
struct SignInDivider: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme == .glass {
            GlassDivider()
        } else {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
        }
    }
}

/// 28 pt step marker: number in a soft disc (todo), provider ring (current), filled check (done).
struct StepIndicator: View {
    let number: Int
    let step: SignInStep
    let kind: ProviderKind
    let glass: Bool
    let scheme: ColorScheme

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        ZStack {
            switch step {
            case .todo:
                if glass {
                    // Dark: a darker disc keeps the light number at 4.5:1; light: unchanged.
                    Circle().fill(scheme == .dark ? Color.black.opacity(0.12) : Color.primary.opacity(0.10))
                    Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(SheetTone.secondary(scheme, glass: true))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 2)
                    Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(SheetTone.secondary(scheme, glass: false))
                }
            case .current:
                // Lifted (dark) / deepened (light) ring clears 3:1 on every card; the number stays primary.
                Circle().strokeBorder(SheetTone.ring(kind, scheme), lineWidth: 2.5)
                Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            case .done:
                Circle().fill(GlassStyle.fill(kind))
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Step \(number), \(phrase)")
    }

    private var phrase: String {
        switch step {
        case .todo: "not started"
        case .current: "current"
        case .done: "done"
        }
    }
}
