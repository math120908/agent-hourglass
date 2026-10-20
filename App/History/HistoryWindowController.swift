import AppKit
import SwiftUI
import UsageCore

/// History window (≈ 760 × 460, resizable). Open counts as foreground for polling.
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    let model: HistoryModel
    private let engine: UsageEngine
    private let entries: () async -> [AccountEntry]
    private var window: NSWindow?

    init(engine: UsageEngine, entries: @escaping () async -> [AccountEntry]) {
        self.engine = engine
        self.entries = entries
        model = HistoryModel(store: engine.history)
    }

    func show(account: AccountID? = nil) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: HistoryView(model: model)))
            w.title = "Usage History"
            w.titleVisibility = .hidden
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 760, height: 460))
            w.center()
            w.delegate = self
            window = w
        }
        let wasVisible = window?.isVisible == true
        Task {
            let e = await entries()
            if let account { model.account = account }
            model.show(entries: e)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { engine.setForeground(true) }
    }

    func windowWillClose(_ notification: Notification) { engine.setForeground(false) }
}
