import AppKit
import SwiftUI
import UsageCore

/// Debug: called from `--render-snapshots <dir>`; writes settings-<tab>-<mode>.png from fixtures.
@MainActor
enum SettingsSnapshotRenderer {
    static func render(to dir: URL) {
        let state = AppState()
        let content = Fixtures.content()
        let entries = content.accounts.enumerated().map { i, a in
            AccountEntry(id: a.id, kind: a.kind, displayName: a.kind == .claude ? "Personal Max" : "Work Copilot",
                         remoteLogin: a.kind == .claude ? "ck@example.com" : "ckuo_LinkedIn",
                         order: i, addedAt: Fixtures.now, status: "ok")
        }
        for a in content.accounts {
            state.accounts.append(a.id)
            state.statuses[a.id] = a.status
            state.snapshots[a.id] = a.snapshot
        }
        let model = SettingsModel(appState: state, backend: nil)
        model.entries = entries
        model.previewMenuBar(entries.first?.id)
        for tab in SettingsTab.allCases {
            for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = SettingsRoot(model: model, tab: tab)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: name)
                host.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
                let w = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                w.appearance = host.appearance
                w.contentView = host
                host.layoutSubtreeIfNeeded()
                host.display()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = dir.appendingPathComponent("settings-\(tab.rawValue.lowercased())-\(mode).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }
}
