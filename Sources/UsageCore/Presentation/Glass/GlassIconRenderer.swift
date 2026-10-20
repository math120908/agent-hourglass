import AppKit

/// Glass (mockup A) menu bar icon: outlined bar, pace line, "→5H" caption underneath.
/// Template in normal/outline; warning/critical carry a yellow/red fill and draw
/// their ink with `labelColor`, resolved at draw time so light and dark bars both work.
public struct GlassIconRenderer: MenuBarIconRendering {
    public static let size = NSSize(width: 30, height: 22)

    public init() {}

    public func image(for state: IconState) -> NSImage {
        if state.level == .empty {
            let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.0percent", accessibilityDescription: "Usage")
            let img = NSImage(size: Self.size, flipped: true) { rect in
                guard let symbol else { return true }
                let s = symbol.size
                let r = NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height)
                symbol.draw(in: r)
                return true
            }
            img.isTemplate = true
            return img
        }
        let colored = state.level == .warning || state.level == .critical
        let img = NSImage(size: Self.size, flipped: true) { _ in
            Self.draw(state, ink: colored ? .labelColor : .black)
            return true
        }
        img.isTemplate = !colored
        img.accessibilityDescription = state.percent.map { "\(state.caption) \($0)%" } ?? state.caption
        return img
    }

    private static func draw(_ state: IconState, ink: NSColor) {
        // Track outline.
        let track = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 27, height: 7), xRadius: 2, yRadius: 2)
        track.lineWidth = 1
        if state.level == .outline { track.setLineDash([2, 1.5], count: 2, phase: 0) }
        ink.withAlphaComponent(0.75).setStroke()
        track.stroke()

        // Fill.
        if state.level != .outline, let p = state.percent, p > 0 {
            let fill: NSColor = switch state.level {
            case .warning: .systemYellow
            case .critical: .systemRed
            default: ink
            }
            fill.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 5, width: max(1.5, 24 * CGFloat(p) / 100), height: 4),
                         xRadius: 1, yRadius: 1).fill()
        }

        // Pace line.
        if state.level != .outline, let pace = state.pace {
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3 + 24 * CGFloat(pace) / 100 - 0.7, y: 2, width: 1.4, height: 10),
                         xRadius: 0.7, yRadius: 0.7).fill()
        }

        // Caption.
        // At warning/critical the percent replaces the arrow so the caption fits in 30 pt.
        var text = "→" + state.caption
        if state.level == .warning || state.level == .critical, let p = state.percent { text = "\(state.caption) \(p)%" }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: ink,
            .paragraphStyle: para,
        ]
        (text as NSString).draw(in: NSRect(x: 0, y: 12.5, width: 30, height: 9), withAttributes: attrs)
    }

    /// Rasterizes `image` at `scale` under the current drawing appearance.
    public static func bitmap(_ image: NSImage, scale: CGFloat) -> NSBitmapImageRep? {
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
