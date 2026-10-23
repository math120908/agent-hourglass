import AppKit
import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

@Suite struct InstrumentIconRendererTests {
    @Test func rendererSizeAndTemplate() {
        let r = InstrumentIconRenderer()
        #expect(r.image(for: .empty).size == NSSize(width: 50, height: 22))
        #expect(r.image(for: .empty).isTemplate)
        #expect(!r.image(for: IconState(level: .critical, percent: 96, pace: nil, caption: "5H", weekly: 91)).isTemplate)
    }
}

@Suite struct InstrumentIconPreview {
    /// Writes light/dark previews when ICON_PREVIEW_DIR is set.
    @Test func writePreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["ICON_PREVIEW_DIR"] else { return }
        let named: [(String, IconState)] = [
            ("normal", IconState(level: .normal, percent: 1, pace: 62, caption: "5H", weekly: 39)),
            ("warn", IconState(level: .warning, percent: 78, pace: 62, caption: "5H", weekly: 62)),
            ("limit", IconState(level: .critical, percent: 96, pace: 62, caption: "5H", weekly: 91)),
            ("stale", IconState(level: .outline, percent: 42, pace: 62, caption: "5H", weekly: 39)),
            ("empty", .empty),
        ]
        for (name, state) in named {
            for (mode, appearance, bg) in [("light", NSAppearance.Name.aqua, NSColor(white: 0.94, alpha: 1)),
                                            ("dark", NSAppearance.Name.darkAqua, NSColor(white: 0.13, alpha: 1))] {
                let icon = InstrumentIconRenderer().image(for: state)
                let canvas = NSImage(size: NSSize(width: 66, height: 24), flipped: false) { rect in
                    bg.setFill(); rect.fill()
                    let target = NSRect(x: 8, y: 1, width: 50, height: 22)
                    if icon.isTemplate {
                        let tinted = NSImage(size: icon.size, flipped: false) { r in
                            icon.draw(in: r); NSColor.labelColor.set(); r.fill(using: .sourceAtop); return true
                        }
                        tinted.draw(in: target)
                    } else {
                        icon.draw(in: target)
                    }
                    return true
                }
                var rep: NSBitmapImageRep?
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    rep = GlassIconRenderer.bitmap(canvas, scale: 4)
                }
                let png = try #require(rep?.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "\(dir)/instr-icon-\(name)-\(mode).png"))
            }
        }
    }
}
