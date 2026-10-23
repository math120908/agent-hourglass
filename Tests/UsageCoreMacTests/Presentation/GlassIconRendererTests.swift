import AppKit
import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

@Suite struct GlassIconRendererTests {
    let r = GlassIconRenderer()
    static let states: [IconState] = [
        IconState(level: .normal, percent: 1, pace: 62, caption: "5H"),
        IconState(level: .warning, percent: 78, pace: 62, caption: "5H"),
        IconState(level: .critical, percent: 96, pace: 62, caption: "5H"),
        IconState(level: .outline, percent: nil, pace: nil, caption: "5H"),
        .empty,
    ]

    @Test(arguments: states) func sizeAndTemplate(_ state: IconState) throws {
        let img = r.image(for: state)
        #expect(img.size == NSSize(width: 42, height: 22))
        #expect(img.isTemplate == (state.level == .empty))
        for scale in [1, 2] {
            let rep = try #require(GlassIconRenderer.bitmap(img, scale: CGFloat(scale)))
            #expect(rep.pixelsWide == 42 * scale)
            #expect(rep.pixelsHigh == 22 * scale)
        }
    }
}

@Suite struct GlassIconPreview {
    /// Writes light/dark previews (menu bar background + icon at 2x) when ICON_PREVIEW_DIR is set.
    @Test func writePreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["ICON_PREVIEW_DIR"] else { return }
        let named: [(String, IconState)] = [
            ("normal", IconState(level: .normal, percent: 1, pace: 62, caption: "5H")),
            ("warn", IconState(level: .warning, percent: 78, pace: 62, caption: "5H")),
            ("limit", IconState(level: .critical, percent: 96, pace: 62, caption: "5H")),
            ("stale", IconState(level: .outline, percent: 42, pace: 62, caption: "5H")),
            ("empty", .empty),
        ]
        for (name, state) in named {
            for (mode, appearance, bg) in [("light", NSAppearance.Name.aqua, NSColor(white: 0.94, alpha: 1)),
                                            ("dark", NSAppearance.Name.darkAqua, NSColor(white: 0.13, alpha: 1))] {
                let icon = GlassIconRenderer().image(for: state)
                let canvas = NSImage(size: NSSize(width: 58, height: 24), flipped: false) { rect in
                    bg.setFill(); rect.fill()
                    let target = NSRect(x: 8, y: 1, width: 42, height: 22)
                    if icon.isTemplate {
                        // Mimic the menu bar tinting template images with the label color.
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
                try png.write(to: URL(fileURLWithPath: "\(dir)/icon-\(name)-\(mode).png"))
            }
        }
    }
}
