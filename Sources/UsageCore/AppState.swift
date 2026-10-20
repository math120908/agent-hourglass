import Foundation
import Observation

/// UI-facing state. A failure never drops the last good snapshot; it only changes the status.
@MainActor @Observable
public final class AppState {
    public var accounts: [AccountID] = []
    public var snapshots: [AccountID: UsageSnapshot] = [:]
    public var statuses: [AccountID: AccountStatus] = [:]
    public var lastSuccess: [AccountID: Date] = [:]
    /// Display name and gh login per account, from the registry.
    public var names: [AccountID: String] = [:]
    public var logins: [AccountID: String] = [:]
    public var isOffline = false
    public var effectiveInterval: Duration = PollSchedule().effectiveInterval(floor: .seconds(60))

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    public func apply(_ id: AccountID, _ outcome: FetchOutcome) {
        if !accounts.contains(id) { accounts.append(id) }
        switch outcome {
        case let .success(snap):
            snapshots[id] = snap
            statuses[id] = .fresh
            lastSuccess[id] = now()
        case let .failure(status):
            statuses[id] = status
        }
    }

    /// Fresh iff the last success is younger than 2 × the effective interval.
    public func isFresh(_ id: AccountID) -> Bool {
        guard let t = lastSuccess[id] else { return false }
        return now().timeIntervalSince(t) < 2 * Backoff.seconds(effectiveInterval)
    }
}
