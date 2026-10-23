import UIKit

/// Runs a pass under a background-task assertion. On expiration the pass is cancelled first (so a
/// `FileRefreshLock` body unwinds and its `defer` releases the App Group flock), then the assertion
/// ends. iOS never suspends the app while it holds the lock (0xdead10cc, design M2).
@MainActor
struct BackgroundAssertion {
    let begin: @MainActor (String, @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    let end: @MainActor (UIBackgroundTaskIdentifier) -> Void

    static var live: BackgroundAssertion {
        BackgroundAssertion(
            begin: { UIApplication.shared.beginBackgroundTask(withName: $0, expirationHandler: $1) },
            end: { UIApplication.shared.endBackgroundTask($0) },
        )
    }

    func run(_ name: String, _ body: @escaping @MainActor () async -> Void) async {
        let work = Task { @MainActor in await body() }
        let ticket = Ticket()
        let end = self.end
        ticket.id = begin(name) {
            work.cancel()
            ticket.finish(end)
        }
        await work.value
        ticket.finish(end)
    }

    @MainActor private final class Ticket {
        var id = UIBackgroundTaskIdentifier.invalid
        func finish(_ end: (UIBackgroundTaskIdentifier) -> Void) {
            guard id != .invalid else { return }
            end(id)
            id = .invalid
        }
    }
}
