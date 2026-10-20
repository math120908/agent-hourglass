import SwiftUI
import UsageCore

/// Glass palette. Accent per provider at normal severity; amber / red take over at warning / critical.
enum GlassStyle {
    static let claude = Color(red: 0.80, green: 0.42, blue: 0.24)
    static let copilot = Color(red: 0.49, green: 0.38, blue: 0.78)
    static let warning = Color(red: 0.86, green: 0.62, blue: 0.10)
    static let critical = Color(red: 0.86, green: 0.25, blue: 0.24)

    static func accent(_ kind: ProviderKind) -> Color { kind == .claude ? claude : copilot }

    static func color(_ severity: Meter.Severity, _ kind: ProviderKind) -> Color {
        switch severity {
        case .normal: accent(kind)
        case .warning: warning
        case .critical: critical
        }
    }
}
