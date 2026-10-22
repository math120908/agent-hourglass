import AppKit
import os
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lock: InstanceLock
    private let appState = AppState()
    private let themeStore = ThemeStore()
    private var statusItem: StatusItemController?
    private var engine: UsageEngine?

    init(lock: InstanceLock) {
        self.lock = lock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = UsageEngine(appState: appState)
        self.engine = engine
        statusItem = StatusItemController(appState: appState, themeStore: themeStore, engine: engine)
        engine.start()
        if LoginItem(service: MainAppLoginService()).reconcile() {
            Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Migration").info("launch at login re-registered")
        }
        // Debug: `--add-copilot <login>` drives the Add Account window's Copilot path once.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--add-copilot"), i + 1 < args.count {
            statusItem?.debugAddCopilot(args[i + 1])
        }
        // Debug: `--add-codex` adds the Codex CLI login once.
        if args.contains("--add-codex") { statusItem?.debugAddCodex() }
        // Debug: `--open-menu` pops the right-click menu after launch (menu verification).
        if args.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.statusItem?.debugMenu() }
        }
        // Debug: `--toggle-first-card` opens the popover, then flips the first card twice (resize check).
        if args.contains("--toggle-first-card") {
            for (n, delay) in [2.0, 4.0, 6.0].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if n == 0 { self?.statusItem?.debugOpen() } else { self?.statusItem?.debugToggleFirstCard() }
                }
            }
        }
    }
}
