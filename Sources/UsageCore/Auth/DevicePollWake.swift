import Foundation

/// Cuts a device-login poll wait short, e.g. when the app returns to the foreground. A wake only
/// lets the poll run once the current interval (including slow_down) has elapsed; it never
/// polls sooner. A fire with nobody waiting is kept for the next wait.
public final class DevicePollWake: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    public init() {}

    public func fire() {
        let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
            let all = Array(waiters.values)
            waiters.removeAll()
            if all.isEmpty { pending = true }
            return all
        }
        resumed.forEach { $0.resume() }
    }

    /// Returns on the next `fire()` (or a kept one), or when the task is cancelled.
    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resumeNow: Bool = lock.withLock {
                    if pending || Task.isCancelled {
                        pending = false
                        return true
                    }
                    waiters[id] = c
                    return false
                }
                if resumeNow { c.resume() }
            }
        } onCancel: {
            lock.withLock { waiters.removeValue(forKey: id) }?.resume()
        }
    }
}
