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
        var lockFreeAtEnd: [Bool] = []
    }

    /// Non-blocking flock probe on a fresh open file description: true when nobody holds the lock.
    static func lockIsFree(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        flock(fd, LOCK_UN)
        return true
    }

    @Test func test_G1_expirationCancelsBodyAndReleasesLock() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "refresh.lock")
        let fake = Fake()
        let assertion = BackgroundAssertion(
            begin: { _, h in fake.handler = h; return UIBackgroundTaskIdentifier(rawValue: 7) },
            end: { fake.lockFreeAtEnd.append(Self.lockIsFree(url)); fake.ended.append($0) },
        )
        let entered = AsyncStream<Void>.makeStream()
        let run = Task { @MainActor in
            await assertion.run("t") {
                _ = try? await FileRefreshLock(url: url, timeout: .seconds(30)).withLock {
                    entered.continuation.yield()
                    do { try await Task.sleep(for: .seconds(20)) } catch {
                        // Slow unwind after cancellation: the lock must still be released before `end`.
                        await Task.detached { try? await Task.sleep(for: .milliseconds(300)) }.value
                        throw error
                    }
                }
            }
        }
        var it = entered.stream.makeAsyncIterator()
        _ = await it.next()
        #expect(!Self.lockIsFree(url))
        fake.handler?()
        let deadline = ContinuousClock.now + .seconds(3)
        while fake.ended.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        #expect(fake.ended == [UIBackgroundTaskIdentifier(rawValue: 7)])
        #expect(fake.lockFreeAtEnd == [true])
        let start = ContinuousClock.now
        try await FileRefreshLock(url: url, timeout: .milliseconds(200)).withLock {}
        #expect(ContinuousClock.now - start < .milliseconds(200))
        await run.value
        #expect(fake.ended.count == 1)
    }
}
