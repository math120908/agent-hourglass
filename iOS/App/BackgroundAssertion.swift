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

    /// iOS allows a few seconds after expiration; stay well inside it.
    static let expirationGrace: Duration = .seconds(2)

    func run(_ name: String, _ body: @escaping @MainActor () async -> Void) async {
        let work = Task { @MainActor in await body() }
        let ticket = Ticket()
        let end = self.end
        ticket.id = begin(name) {
            work.cancel()
            // Cancellation is cooperative: wait (bounded) for the body to unwind and release the
            // flock before ending the assertion, else iOS may suspend us holding it (0xdead10cc).
            Task { @MainActor in
                let deadline = Task { try? await Task.sleep(for: Self.expirationGrace) }
                let done = Task { @MainActor in await work.value; deadline.cancel() }
                await deadline.value
                done.cancel()
                ticket.finish(end)
            }
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
