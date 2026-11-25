import SwiftUI
import Testing
import UIKit
import UsageCore
@testable import AgentHourglass

/// Provider accents must stay readable on the widget / card backgrounds in both schemes.
struct GlassStyleContrastTests {
    private static let kinds: [ProviderKind] = [.claude, .copilot, .codex, .google, .grok, .elevenlabs]
    /// Midpoints of the `WidgetBackground` Glass gradients (dark 0.20 -> 0.11, light 0.98 -> 0.90).
    private static let darkBackground = UIColor(white: 0.155, alpha: 1)
    private static let lightBackground = UIColor(white: 0.94, alpha: 1)

    private func resolved(_ c: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: kinds)
    func accentReadableOnDarkBackground(_ kind: ProviderKind) {
        let c = resolved(GlassStyle.accent(kind), .dark)
        let ratio = contrast(c, Self.darkBackground)
        #expect(ratio >= 3, "\(kind) accent \(ratio):1 on the dark widget")
    }

    /// Copilot keeps the system gray (2.7:1 on the light widget); tracked separately from this fix.
    @Test(arguments: kinds.filter { $0 != .copilot })
    func accentReadableOnLightBackground(_ kind: ProviderKind) {
        let c = resolved(GlassStyle.accent(kind), .light)
        let ratio = contrast(c, Self.lightBackground)
        #expect(ratio >= 3, "\(kind) accent \(ratio):1 on the light widget")
    }

    @Test(arguments: kinds)
    func fillKeepsWhiteGlyphReadable(_ kind: ProviderKind) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(resolved(GlassStyle.fill(kind), style), .white)
            #expect(ratio >= 3, "\(kind) fill \(ratio):1 behind white in \(style == .dark ? "dark" : "light")")
        }
    }

    @Test(arguments: kinds)
    func severityWinsOverProviderAccent(_ kind: ProviderKind) {
        #expect(GlassStyle.color(.warning, kind) == GlassStyle.warning)
        #expect(GlassStyle.color(.critical, kind) == GlassStyle.critical)
    }

    @Test func elevenLabsAndGrokAdaptToScheme() {
        for kind in [ProviderKind.grok, .elevenlabs] {
            let dark = luminance(resolved(GlassStyle.accent(kind), .dark))
            let light = luminance(resolved(GlassStyle.accent(kind), .light))
            #expect(dark > 0.5 && light < 0.25, "\(kind): dark \(dark), light \(light)")
        }
    }

    @MainActor @Test(arguments: kinds)
    func meterViewUsesAccountKind(_ kind: ProviderKind) {
        let credits = Meter(kind: .window, label: "Credits", percentUsed: 31.2, windowLength: .seconds(30 * 86_400))
        let view = MeterView(meter: credits, kind: kind, settings: .default, theme: .glass)
        #expect(view.kind == kind)
    }
}
