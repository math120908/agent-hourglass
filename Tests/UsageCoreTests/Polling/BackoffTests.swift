import Foundation
import Testing
@testable import UsageCore

struct BackoffTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func retryAfterHonoredMin60() {
        var b = Backoff(jitter: { 0 })
        #expect(b.next(retryAfter: .seconds(5), now: now) == now.addingTimeInterval(60))
        #expect(b.next(retryAfter: .seconds(300), now: now) == now.addingTimeInterval(300))
    }

    @Test func exponentialCapped30m() {
        var b = Backoff(jitter: { 0 })
        let waits = (0..<6).map { _ in b.next(retryAfter: nil, now: now).timeIntervalSince(now) }
        #expect(waits == [120, 240, 480, 960, 1800, 1800])
        var hi = Backoff(jitter: { 0.1 })
        #expect(abs(hi.next(retryAfter: nil, now: now).timeIntervalSince(now) - 132) < 1e-9)
    }

    @Test func resetAfterSuccess() {
        var b = Backoff(jitter: { 0 })
        _ = b.next(retryAfter: nil, now: now)
        _ = b.next(retryAfter: nil, now: now)
        b.reset()
        #expect(b.next(retryAfter: nil, now: now).timeIntervalSince(now) == 120)
    }
}
