import SwiftUI
import UsageCore
import WidgetKit

enum WidgetRenderMode: Sendable { case fullColor, accented, vibrant }

/// Colors for one widget render. Accented and vibrant never get full-color fills or opaque backgrounds.
struct WidgetRenderStyle: Sendable {
    var mode: WidgetRenderMode
    var theme: Theme
    var colorScheme: ColorScheme
    /// Set only by the render harness; production leaves it nil.
    var previewAccent: Color? = nil

    init(mode: WidgetRenderMode, theme: Theme, colorScheme: ColorScheme, previewAccent: Color? = nil) {
        self.mode = mode
        self.theme = theme
        self.colorScheme = colorScheme
        self.previewAccent = previewAccent
    }

    init(_ mode: WidgetRenderingMode, theme: Theme, colorScheme: ColorScheme) {
        let m: WidgetRenderMode
        switch mode {
        case .accented: m = .accented
        case .vibrant: m = .vibrant
        default: m = .fullColor
        }
        self.init(mode: m, theme: theme, colorScheme: colorScheme)
    }

    var isFullColor: Bool { mode == .fullColor }

    func fill(_ severity: Meter.Severity, _ kind: ProviderKind) -> Color {
        isFullColor ? GlassStyle.color(severity, kind) : (previewAccent ?? .white)
    }

    func track() -> Color {
        guard isFullColor else { return .white.opacity(0.25) }
        return .primary.opacity(theme == .glass ? 0.09 : 0.10)
    }

    /// Ring track; matches Mac `RingGauge` in full color.
    func ringTrack() -> Color { isFullColor ? .primary.opacity(0.10) : .white.opacity(0.25) }

    /// Pace tick; matches Mac `GlassMeterBar` in full color.
    func paceTick() -> Color { isFullColor ? .primary.opacity(0.55) : .white.opacity(0.55) }

    func text(_ level: GlassTone.Level) -> Color {
        guard isFullColor, colorScheme == .light else {
            switch level {
            case .secondary: return .white.opacity(0.90)
            case .tertiary: return .white.opacity(0.70)
            case .pill: return .white.opacity(0.96)
            }
        }
        return level == .tertiary ? .primary.opacity(0.55) : .primary.opacity(0.75)
    }

    func dimmed(_ isDimmed: Bool) -> Double { isDimmed ? 0.45 : 1.0 }

    var critical: Color { isFullColor ? GlassStyle.critical : (previewAccent ?? .white) }
}

/// The full-color widget background, shared by the container background and the render harness.
struct WidgetBackground: View {
    var style: WidgetRenderStyle

    var body: some View {
        switch style.theme {
        case .glass:
            LinearGradient(
                colors: style.colorScheme == .dark
                    ? [Color(white: 0.20), Color(white: 0.11)]
                    : [Color(white: 0.98), Color(white: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .instrument:
            style.colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96)
        }
    }
}

extension View {
    /// The only background a widget draws; the system removes it in tinted and clear modes.
    func widgetContainerBackground(style: WidgetRenderStyle) -> some View {
        containerBackground(for: .widget) { WidgetBackground(style: style) }
    }
}
