import Foundation

/// Spec §6: popover open → user interval (floored per provider); closed → every account at ≥ 300 s.
public struct PollSchedule: Sendable, Equatable {
    public static let backgroundInterval: Duration = .seconds(300)

    public var userInterval: Duration = .seconds(60)
    public var isForeground: Bool

    public init(userInterval: Duration = .seconds(60), isForeground: Bool = false) {
        self.userInterval = userInterval
        self.isForeground = isForeground
    }

    public func effectiveInterval(floor: Duration) -> Duration {
        isForeground ? max(userInterval, floor) : max(Self.backgroundInterval, userInterval, floor)
    }
}

/// Stable per-account offset in [0, interval). FNV-1a, because `hashValue` is reseeded every launch.
public func staggerOffset(for id: AccountID, interval: Duration) -> Duration {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in id.rawValue.utf8 {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01b3
    }
    let ms = max(Int64(Backoff.seconds(interval) * 1000), 1)
    return .milliseconds(Int64(h % UInt64(ms)))
}
