import SwiftUI
import UsageCore

/// Glass palette. Accent per provider at normal severity; amber / red take over at warning / critical.
enum GlassStyle {
    static let claude = Color(red: 0.80, green: 0.42, blue: 0.24)
    /// Codex: neutral teal, clear of Claude orange.
    static let codex = Color(red: 0.05, green: 0.52, blue: 0.50)
    static let warning = Color(red: 0.86, green: 0.62, blue: 0.10)
    static let critical = Color(red: 0.86, green: 0.25, blue: 0.24)

    /// Lighter text variant of a chip tint for the dark card.
    static func darkText(_ tint: Color) -> Color {
        tint == critical ? Color(red: 1.0, green: 0.93, blue: 0.91) : Color(red: 1.0, green: 0.92, blue: 0.74)
    }

    static func accent(_ kind: ProviderKind) -> Color {
        switch kind {
        case .claude: claude
        case .copilot: Color.gray
        case .codex: codex
        }
    }

    static func color(_ severity: Meter.Severity, _ kind: ProviderKind) -> Color {
        switch severity {
        case .normal: accent(kind)
        case .warning: warning
        case .critical: critical
        }
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
