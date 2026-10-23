import Foundation

/// Removes an account's stored history. P5's `HistoryStore` conforms; until then `NoHistory` is used.
public protocol HistoryDeleting: Sendable {
    func deleteAccount(_ id: AccountID) async throws
}

public struct NoHistory: HistoryDeleting {
    public init() {}
    public func deleteAccount(_ id: AccountID) async throws {}
}

/// Accepts successful snapshots for history. `HistoryStore` conforms; the Poller holds an optional one.
public protocol HistoryRecording: Sendable {
    func record(_ snapshot: UsageSnapshot) async throws
}
