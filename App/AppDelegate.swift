import AppKit
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
        // Debug: `--add-copilot <login>` drives the Add Account window's Copilot path once.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--add-copilot"), i + 1 < args.count {
            statusItem?.debugAddCopilot(args[i + 1])
        }
    }
}
