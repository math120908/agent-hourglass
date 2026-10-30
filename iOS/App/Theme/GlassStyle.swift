import SwiftUI
import UsageCore

/// Glass palette. Accent per provider at normal severity; amber / red take over at warning / critical.
enum GlassStyle {
    static let claude = Color(red: 0.80, green: 0.42, blue: 0.24)
    /// Codex: neutral teal, clear of Claude orange.
    static let codex = Color(red: 0.05, green: 0.52, blue: 0.50)
    /// Deeper teal for filled controls (prominent buttons, done discs): white label 5.2:1, where
    /// `codex` gives 4.48:1. Bars, icons and chips keep `codex`.
    static let codexFill = Color(red: 0.045, green: 0.48, blue: 0.46)
    static let warning = Color(red: 0.86, green: 0.62, blue: 0.10)
    static let critical = Color(red: 0.86, green: 0.25, blue: 0.24)

    /// Lighter text variant of a chip tint for the dark card.
    static func darkText(_ tint: Color) -> Color {
        tint == critical ? Color(red: 1.0, green: 0.93, blue: 0.91) : Color(red: 1.0, green: 0.92, blue: 0.74)
    }

    /// Dark-mode text level for a severity: the provider accent (same hue as the bar fill), lifted amber / red.
    static func darkAccent(_ severity: Meter.Severity, _ kind: ProviderKind) -> Color {
        switch severity {
        case .normal: accent(kind)
        case .warning: Color(red: 1.0, green: 0.82, blue: 0.45)
        case .critical: Color(red: 1.0, green: 0.66, blue: 0.62)
        }
    }

    static func accent(_ kind: ProviderKind) -> Color {
        switch kind {
        case .claude: claude
        case .copilot: Color.gray
        case .codex: codex
        case .google: Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }

    /// Fill behind a white label or glyph: `codexFill` for Codex, the accent otherwise.
    static func fill(_ kind: ProviderKind) -> Color {
        kind == .codex ? codexFill : accent(kind)
    }

    static func color(_ severity: Meter.Severity, _ kind: ProviderKind) -> Color {
        switch severity {
        case .normal: accent(kind)
        case .warning: warning
        case .critical: critical
        }
    }
}

/// Hairline section divider; the system `Divider` vanishes on the dark glass card.
struct GlassDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.primary.opacity(0.12))
            .frame(height: 0.5)
    }
}

/// Secondary / tertiary text on the Glass card. Light mode keeps the system hierarchical styles;
/// dark mode uses explicit white levels because the soft-light card lift washes `.secondary`
/// out to ~1.6:1. Values are tuned for WCAG AA on the dark card (text >= 4.5:1, glyphs >= 3:1).
struct GlassTone: ViewModifier {
    enum Level { case secondary, tertiary, pill }
    var level: Level
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.foregroundStyle(style)
    }

    private var style: AnyShapeStyle {
        guard scheme == .dark else {
            return level == .tertiary ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
        }
        switch level {
        case .secondary: return AnyShapeStyle(Color.white.opacity(0.90))
        case .tertiary: return AnyShapeStyle(Color.white.opacity(0.70))
        case .pill: return AnyShapeStyle(Color.white.opacity(0.96))
        }
    }
}

extension View {
    func glassTone(_ level: GlassTone.Level = .secondary) -> some View { modifier(GlassTone(level: level)) }
}
