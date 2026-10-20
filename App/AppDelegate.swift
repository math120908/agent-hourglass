import AppKit
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lock: InstanceLock
    private let appState = AppState()
    private let themeStore = ThemeStore()
    private var statusItem: StatusItemController?
    private var pathTask: Task<Void, Never>?

    init(lock: InstanceLock) {
        self.lock = lock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(appState: appState, themeStore: themeStore)
        pathTask = Task { [appState] in
            for await online in PathMonitor.updates() {
                appState.isOffline = !online
            }
        }
    }
}
