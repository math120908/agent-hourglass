import Foundation

/// 429 backoff for one account. Retry-After wins (floored at 60 s); otherwise 2, 4, 8 … min, capped at 30 min, ±10% jitter.
public struct Backoff: Sendable {
    public static let floor: Duration = .seconds(60)
    public static let cap: Duration = .seconds(30 * 60)

    public private(set) var consecutive429 = 0
    private let jitter: @Sendable () -> Double

    /// `jitter` returns a factor in [-0.1, 0.1].
    public init(jitter: @escaping @Sendable () -> Double = { Double.random(in: -0.1...0.1) }) {
        self.jitter = jitter
    }

    public mutating func next(retryAfter: Duration?, now: Date) -> Date {
        consecutive429 += 1
        if let retryAfter {
            return now.addingTimeInterval(Self.seconds(max(retryAfter, Self.floor)))
        }
        let base = min(120 * pow(2, Double(consecutive429 - 1)), Self.seconds(Self.cap))
        return now.addingTimeInterval(base * (1 + jitter()))
    }

    public mutating func reset() { consecutive429 = 0 }

    static func seconds(_ d: Duration) -> TimeInterval {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}
