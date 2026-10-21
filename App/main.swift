import AppKit
import UsageCore

MainActor.assumeIsolated {
    _ = NSApplication.shared
    SnapshotRenderer.runIfRequested()
    StateGalleryRenderer.runIfRequested()
    HistorySnapshotRenderer.runIfRequested()
}

let lock: InstanceLock
do {
    lock = try InstanceLock.acquire()
} catch InstanceLock.Error.alreadyRunning {
    exit(0)
} catch {
    NSLog("AgentHourglass: instance lock failed: %@", String(describing: error))
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(lock: lock)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
