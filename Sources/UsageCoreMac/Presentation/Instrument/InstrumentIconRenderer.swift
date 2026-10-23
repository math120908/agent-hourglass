import UsageCore
import AppKit

/// Instrument (mockup B) menu bar icon: session and weekly mini bars stacked, then the session %.
/// Template while every bar is neutral; colored bars draw their ink with `labelColor`.
public struct InstrumentIconRenderer: MenuBarIconRendering {
    public static let size = NSSize(width: 50, height: 22)

    public init() {}

    public func image(for state: IconState) -> NSImage {
        if state.level == .empty {
            let img = GlassIconRenderer().image(for: .empty)
            let out = NSImage(size: Self.size, flipped: true) { rect in
                img.draw(in: NSRect(x: (rect.width - img.size.width) / 2, y: 0, width: img.size.width, height: img.size.height))
                return true
            }
            out.isTemplate = true
            return out
        }
        let layout = InstrumentIconLayout(state)
        let img = NSImage(size: Self.size, flipped: true) { _ in
            Self.draw(layout, ink: layout.isTemplate ? .black : .labelColor)
            return true
        }
        img.isTemplate = layout.isTemplate
        img.accessibilityDescription = "Session \(layout.text)" + (state.weekly.map { ", week \($0)%" } ?? "")
        return img
    }

    private static func draw(_ layout: InstrumentIconLayout, ink: NSColor) {
        func color(_ tone: InstrumentIconLayout.Tone) -> NSColor {
            switch tone {
            case .ink: ink
            case .warning: .systemYellow
            case .critical: .systemRed
            }
        }
        let rows: [(CGFloat, Double?, InstrumentIconLayout.Tone, CGFloat)] = [
            (5, layout.sessionFraction, layout.sessionTone, 1),
            (12.5, layout.weeklyFraction, layout.weeklyTone, 0.85),
        ]
        for (y, fraction, tone, alpha) in rows {
            let track = NSBezierPath(roundedRect: NSRect(x: 1.5, y: y + 0.5, width: 17, height: 3.5), xRadius: 1.75, yRadius: 1.75)
            track.lineWidth = 1
            if layout.dashed { track.setLineDash([2, 1.5], count: 2, phase: 0) }
            ink.withAlphaComponent(0.6).setStroke()
            track.stroke()
            if let fraction, fraction > 0 {
                color(tone).withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: max(2, 18 * CGFloat(fraction)), height: 4.5),
                             xRadius: 2.25, yRadius: 2.25).fill()
            }
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: color(layout.sessionTone),
        ]
        (layout.text as NSString).draw(at: NSPoint(x: 21, y: 4), withAttributes: attrs)
    }
}
