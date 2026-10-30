import SwiftUI
import UsageCore

/// Colors for the add-account sheets, tuned for WCAG AA on the sheet card in both themes:
/// text >= 4.5:1, essential glyphs and rings >= 3:1. The Glass dark card is a mid grey
/// (luminance ~0.15), so the stock accents fall short there and get lifted variants.
enum SheetTone {
    /// Success glyph: `HomeHeader` fresh green on dark, a deep green on light.
    static func success(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.59, green: 0.93, blue: 0.59) : Color(red: 0.10, green: 0.50, blue: 0.22)
    }

    /// Error glyph (field mark, failure icon).
    static func criticalGlyph(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.0, green: 0.78, blue: 0.75) : Color(red: 0.70, green: 0.18, blue: 0.15)
    }

    /// Error text on the card. Glass dark needs the near-white red to clear 4.5:1 on the grey card.
    static func criticalText(_ scheme: ColorScheme, glass: Bool) -> Color {
        guard scheme == .dark else { return Color(red: 0.70, green: 0.18, blue: 0.15) }
        return glass ? GlassStyle.darkText(GlassStyle.critical) : GlassStyle.darkAccent(.critical, .claude)
    }

    /// Claude accent for rings and quiet labels: lifted on dark, deepened on light.
    static func claude(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.0, green: 0.76, blue: 0.60) : Color(red: 0.72, green: 0.35, blue: 0.18)
    }

    /// Current-step ring: Claude keeps its ring tone, other kinds use their readable accent.
    static func ring(_ kind: ProviderKind, _ scheme: ColorScheme) -> Color {
        kind == .claude ? claude(scheme) : accentText(kind, scheme)
    }

    /// Accent label on a quiet (tinted) pill: lifted on dark, deep on light, >= 4.5:1 on the pill.
    static func accentText(_ kind: ProviderKind, _ scheme: ColorScheme) -> Color {
        switch (kind, scheme) {
        case (.codex, .dark): Color(red: 0.55, green: 0.92, blue: 0.88)
        case (.codex, _): Color(red: 0.0, green: 0.32, blue: 0.30)
        case (.google, .dark): Color(red: 0.78, green: 0.86, blue: 1.0)
        case (.google, _): Color(red: 0.08, green: 0.28, blue: 0.66)
        case (.grok, .dark): Color(red: 0.86, green: 0.88, blue: 0.92)
        case (.grok, _): Color(red: 0.24, green: 0.26, blue: 0.31)
        case (_, .dark): claude(.dark)
        default: Color(red: 0.52, green: 0.22, blue: 0.10)
        }
    }

    /// Secondary text that still clears 4.5:1 (system `.secondary` is ~3.4:1 on white and ~2.4:1
    /// on the Glass light gradient; 0.66 black gives ~4.9:1 on that gradient).
    static func secondary(_ scheme: ColorScheme, glass: Bool) -> AnyShapeStyle {
        if scheme == .light { return AnyShapeStyle(Color.black.opacity(0.66)) }
        return glass ? AnyShapeStyle(Color.white.opacity(0.90)) : AnyShapeStyle(.secondary)
    }
}

/// The sheet surface: the Glass card on Glass, nothing on Instrument (hairline list instead).
struct SheetCard: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme == .glass {
            content.glassCardBackground()
        } else {
            content
        }
    }
}

extension View {
    func sheetCard() -> some View { modifier(SheetCard()) }
}

extension View {
    /// Secondary capsule button. The stock `.bordered` label is the accent on an accent-tinted
    /// pill (2.3 to 3.8:1, ~1.4:1 on the grey Glass dark card), so the label takes `accentText`
    /// and on Glass dark the pill is darkened instead of tinted. That dark pill is drawn as an
    /// explicit background so it survives `.disabled` (the system drops its own fill there).
    @ViewBuilder func quietBordered(_ kind: ProviderKind, scheme: ColorScheme, glass: Bool) -> some View {
        let label = foregroundStyle(SheetTone.accentText(kind, scheme))
        if glass, scheme == .dark {
            label.buttonStyle(.bordered).tint(.clear)
                .background(Capsule().fill(Color.black.opacity(0.28)))
        } else {
            label.buttonStyle(.bordered)
        }
    }
}

/// Outcome line on the card: colored glyph carries the status, the text stays primary so it reads
/// on every surface (a mid green or red label sits near 1:1 on the Glass light gradient).
struct SheetStatus: View {
    let text: String
    let systemImage: String
    let tint: Color
    var font: Font = .headline

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(font)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Disabled primary: a faded provider capsule with a readable label, so the user sees where the
/// action will appear. Enabled callers use `.borderedProminent`; this only draws the disabled look.
/// `compact` matches a regular-size capsule (the Codex `Copy` pill; the system one renders 37 pt)
/// instead of a large button.
struct FadedProminentStyle: ButtonStyle {
    var kind: ProviderKind = .claude
    let tint: Color
    var compact = false
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.78) : SheetTone.accentText(kind, .light))
            .padding(.horizontal, compact ? 14 : 20)
            .frame(minHeight: compact ? 37 : 50)
            .background {
                // Light: a white base keeps the faded tint (and its label contrast) the same on
                // the lilac Glass gradient and on white.
                if scheme == .dark {
                    Capsule().fill(tint.opacity(0.38))
                } else {
                    Capsule().fill(.white).overlay(Capsule().fill(tint.opacity(0.22)))
                }
            }
    }
}
