import AppKit
import SwiftUI
import UsageCore

/// Debug: `ClaudeUsage --render-states <dir>` writes one popover + one menu bar icon PNG per
/// account state (spec §9) in light and dark, then exits. `--theme instrument` writes
/// `instr-state-<name>-<mode>.png` popovers instead (no icons).
@MainActor
enum StateGalleryRenderer {
    struct Case {
        var name: String
        var account: PopoverAccount
        var isOffline = false
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-states"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let theme: Theme = args.firstIndex(of: "--theme").flatMap { $0 + 1 < args.count ? Theme(rawValue: args[$0 + 1]) : nil } ?? .glass
        let base = Fixtures.content()
        for c in cases(base) {
            var content = base
            content.accounts = [c.account]
            content.isOffline = c.isOffline
            let icon = IconState.make(
                appState: c.account.snapshot.map { [c.account.id: $0] } ?? [:],
                statuses: [c.account.id: c.account.status],
                menuBarAccount: c.account.id,
                order: [c.account.id],
                now: base.now
            )
            for (mode, ap) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let root = PopoverRoot(theme: theme, initiallyExpanded: [c.account.id]) { content }
                if theme == .instrument {
                    SnapshotRenderer.write(root, appearance: ap, to: dir.appendingPathComponent("instr-state-\(c.name)-\(mode).png"))
                    continue
                }
                SnapshotRenderer.write(root, appearance: ap, to: dir.appendingPathComponent("state-\(c.name)-\(mode).png"))
                writeIcon(icon, appearance: ap, to: dir.appendingPathComponent("state-\(c.name)-icon-\(mode).png"))
            }
        }
        exit(0)
    }

    static func cases(_ base: PopoverContent) -> [Case] {
        let claude = base.accounts[0], copilot = base.accounts[1], codex = base.accounts[2]
        func with(_ a: PopoverAccount, _ status: AccountStatus, _ edit: (inout PopoverAccount) -> Void = { _ in }) -> PopoverAccount {
            var a = a
            a.status = status
            edit(&a)
            return a
        }
        let old = base.now.addingTimeInterval(-23 * 60)
        return [
            Case(name: "fresh", account: claude),
            Case(name: "stale", account: with(claude, .stale) { $0.snapshot?.fetchedAt = old }),
            Case(name: "ratelimited", account: with(claude, .rateLimited(retryAt: base.now.addingTimeInterval(300)))),
            Case(name: "offline", account: with(claude, .offline), isOffline: true),
            Case(name: "needslogin-claude", account: with(claude, .needsLogin) { $0.snapshot?.fetchedAt = old }),
            Case(name: "needslogin-copilot", account: with(copilot, .needsLogin)),
            Case(name: "ghmissing", account: with(copilot, .ghMissing) { $0.snapshot = nil }),
            Case(name: "ghloginremoved", account: with(copilot, .ghLoginRemoved) { $0.login = "ckuo_LinkedIn" }),
            Case(name: "schemaerror", account: with(claude, .schemaError)),
            Case(name: "nodata", account: with(claude, .noData) { $0.snapshot = nil }),
            Case(name: "cantsave", account: with(claude, .stale) { $0.saveFailed = true }),
            Case(name: "resetting", account: with(claude, .fresh) {
                $0.snapshot?.meters[0].resetsAt = base.now.addingTimeInterval(-60)
                $0.snapshot?.meters[0].percentUsed = 64
            }),
            Case(name: "extradisabled", account: claude),
            Case(name: "codex-fresh", account: codex),
            Case(name: "codex-notsignedin", account: with(codex, .codexNotSignedIn) { $0.snapshot = nil }),
            Case(name: "codex-warning", account: with(codex, .fresh) { $0.snapshot?.meters[0].percentUsed = 81 }),
            Case(name: "copilot-notincluded", account: with(copilot, .fresh) {
                $0.snapshot?.meters[0].limit = 0
                $0.snapshot?.meters[0].used = 0
                $0.snapshot?.meters[0].percentUsed = nil
            }),
        ]
    }

    /// The icon at 4x on a menu-bar-like strip; template images tinted like the real menu bar.
    private static func writeIcon(_ state: IconState, appearance: NSAppearance.Name, to url: URL) {
        let ap = NSAppearance(named: appearance)!
        let size = NSSize(width: 46, height: 26)
        let out = NSImage(size: size)
        out.lockFocus()
        ap.performAsCurrentDrawingAppearance {
            (appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.17, alpha: 1)).setFill()
            NSRect(origin: .zero, size: size).fill()
            let icon = GlassIconRenderer().image(for: state)
            let rect = NSRect(x: 8, y: 2, width: GlassIconRenderer.size.width, height: GlassIconRenderer.size.height)
            if icon.isTemplate {
                let tinted = NSImage(size: icon.size, flipped: false) { r in
                    icon.draw(in: r)
                    NSColor.labelColor.set()
                    r.fill(using: .sourceIn)
                    return true
                }
                tinted.draw(in: rect)
            } else {
                icon.draw(in: rect)
            }
        }
        out.unlockFocus()
        guard let rep = GlassIconRenderer.bitmap(out, scale: 4) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
