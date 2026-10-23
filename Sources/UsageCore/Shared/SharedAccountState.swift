import Foundation

/// Cross-process state for one App Group directory: snapshot cache, refresh lock, shared backoff.
public struct SharedAccountState: Sendable {
    public let cache: SnapshotCache
    public let lock: FileRefreshLock
    public let backoff: SharedBackoffStore

    public init(cache: SnapshotCache, lock: FileRefreshLock, backoff: SharedBackoffStore) {
        self.cache = cache
        self.lock = lock
        self.backoff = backoff
    }

    public static func inDirectory(_ dir: URL) -> SharedAccountState {
        SharedAccountState(
            cache: SnapshotCache(directory: dir),
            lock: FileRefreshLock(url: dir.appendingPathComponent("refresh.lock", isDirectory: false)),
            backoff: SharedBackoffStore(directory: dir)
        )
    }
}
