import Foundation
import Testing
import UIKit
import UsageCore
@testable import AgentHourglass

@MainActor
struct BackgroundAssertionTests {
    @MainActor final class Fake {
        var handler: (@MainActor @Sendable () -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []
    }

    @Test func test_G1_expirationCancelsBodyAndReleasesLock() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "refresh.lock")
        let fake = Fake()
        let assertion = BackgroundAssertion(
            begin: { _, h in fake.handler = h; return UIBackgroundTaskIdentifier(rawValue: 7) },
            end: { fake.ended.append($0) },
        )
        let entered = AsyncStream<Void>.makeStream()
        let run = Task { @MainActor in
            await assertion.run("t") {
                _ = try? await FileRefreshLock(url: url, timeout: .seconds(30)).withLock {
                    entered.continuation.yield()
                    try await Task.sleep(for: .seconds(20))
                }
            }
        }
        var it = entered.stream.makeAsyncIterator()
        _ = await it.next()
        fake.handler?()
        #expect(fake.ended == [UIBackgroundTaskIdentifier(rawValue: 7)])
        let start = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: .milliseconds(200)).withLock {}
        #expect(ContinuousClock.now - start < .milliseconds(200))
        await run.value
        #expect(fake.ended.count == 1)
    }
}
