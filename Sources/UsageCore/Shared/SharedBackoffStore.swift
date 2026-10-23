import Foundation
import os

/// Next allowed fetch time per account at `<directory>/backoff/<SharedFileName>.json`, shared by the
/// iOS app and widget. A plain register (later write wins). Directory 0700, files 0600, no caching.
public struct SharedBackoffStore: Sendable {
    /// Upper bound on how far ahead a value read from disk may gate fetching.
    static let maxGate: TimeInterval = 3600

    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "SharedBackoff")
    private struct Record: Codable { var nextAllowedFetch: Double }

    private let backoff: URL

    public init(directory: URL) {
        backoff = directory.appendingPathComponent("backoff", isDirectory: true)
    }

    func url(for id: AccountID) -> URL {
        backoff.appendingPathComponent(SharedFileName.forAccount(id) + ".json", isDirectory: false)
    }

    /// nil when unset, unreadable, or corrupt (no gate). Clamped to at most `now + 1 h`.
    public func nextAllowedFetch(_ id: AccountID) -> Date? {
        nextAllowedFetch(id, now: Date())
    }

    func nextAllowedFetch(_ id: AccountID, now: Date) -> Date? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        guard let record = try? JSONDecoder().decode(Record.self, from: data),
              record.nextAllowedFetch.isFinite
        else {
            Self.log.notice("ignoring unreadable backoff file")
            return nil
        }
        return min(Date(timeIntervalSince1970: record.nextAllowedFetch), now.addingTimeInterval(Self.maxGate))
    }

    public func setNextAllowedFetch(_ date: Date, for id: AccountID) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backoff, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backoff.path)
        SnapshotCache.protect(backoff)
        let target = url(for: id)
        try AppSupport.secureWrite(JSONEncoder().encode(Record(nextAllowedFetch: date.timeIntervalSince1970)), to: target)
        SnapshotCache.protect(target)
    }
}
