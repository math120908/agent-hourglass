import AppKit
import SwiftUI
import UsageCore

/// Debug: `ClaudeUsage --render-snapshots <dir>` writes popover PNGs (light/dark, collapsed/expanded) and exits.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let content = Fixtures.content()
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (state, expanded) in [("collapsed", Set<AccountID>()), ("expanded", Set(content.accounts.map(\.id)))] {
                let root = PopoverRoot(theme: .glass, initiallyExpanded: expanded) { content }
                write(root, appearance: appearance, to: dir.appendingPathComponent("popover-\(mode)-\(state).png"))
            }
        }
        exit(0)
    }

    private static func write(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let backdrop = view.background(
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.68, blue: 0.86), Color(red: 0.78, green: 0.62, blue: 0.74)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        let host = NSHostingView(rootView: backdrop)
        host.appearance = NSAppearance(named: appearance)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
