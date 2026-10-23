import AppKit
import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

@Suite struct IconStateTests {
    let now = Date(timeIntervalSince1970: 1_800_023_520)
    let a = AccountID(kind: .claude, remoteID: "a")
    let b = AccountID(kind: .copilot, remoteID: "b")

    func claude(_ p: Double, resetsIn: TimeInterval = 3 * 3600) -> UsageSnapshot {
        UsageSnapshot(accountID: a, fetchedAt: now, plan: nil, meters: [
            Meter(kind: .session5h, label: "Session usage", percentUsed: p,
                  resetsAt: now.addingTimeInterval(resetsIn), windowLength: .seconds(5 * 3600)),
        ], spend: nil)
    }
    func copilot(_ p: Double) -> UsageSnapshot {
        UsageSnapshot(accountID: b, fetchedAt: now, plan: nil, meters: [
            Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: p, used: p, limit: 100),
        ], spend: nil)
    }
    func make(_ snaps: [AccountID: UsageSnapshot], _ statuses: [AccountID: AccountStatus] = [:],
              menuBar: AccountID? = nil, order: [AccountID]? = nil) -> IconState {
        IconState.make(appState: snaps, statuses: statuses, menuBarAccount: menuBar,
                       order: order ?? [a, b].filter { snaps[$0] != nil }, now: now)
    }

    @Test func noAccountsEmpty() {
        #expect(make([:]) == .empty)
    }

    @Test func thresholds() {
        #expect(make([a: claude(74)]).level == .normal)
        #expect(make([a: claude(75)]).level == .warning)
        #expect(make([a: claude(89.6)]).level == .critical) // rounds to 90
        #expect(make([a: claude(90)]) == IconState(level: .critical, percent: 90, pace: 40, caption: "5H"))
    }

    @Test func paceFromWindow() {
        #expect(make([a: claude(10, resetsIn: 3 * 3600)]).pace == 40)
    }

    @Test func staleOutline() {
        let s = make([a: claude(42)], [a: .stale])
        #expect(s.level == .outline)
        #expect(s.percent == 42)
    }

    @Test func needsLoginOutline() {
        #expect(make([a: claude(42)], [a: .needsLogin]).level == .outline)
    }

    @Test func menuBarAccountMissingFallsBack() {
        let gone = AccountID(kind: .claude, remoteID: "gone")
        let s = make([b: copilot(33)], menuBar: gone, order: [b])
        #expect(s.percent == 33)
        #expect(s.caption == "PR")
    }

    @Test func menuBarAccountPicked() {
        #expect(make([a: claude(10), b: copilot(80)], menuBar: b).percent == 80)
    }

    @Test func equalStateNoRedraw() {
        #expect(make([a: claude(42.2)]) == make([a: claude(41.8)]))
        #expect(make([a: claude(42)]) != make([a: claude(43)]))
    }
}

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
