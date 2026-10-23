import Foundation
import os

public enum FileRefreshLockError: Error, Equatable, Sendable {
    case timeout
    case open(errno: Int32)
}

/// Cross-process refresh lock (`flock(2)`) shared by the iOS app and widget.
///
/// Each `withLock` call opens its own fd, so two holders in one process exclude each other exactly
/// as two processes do. The lock is held only for `body` and never stored between calls; the fd is
/// unlocked and closed in `defer` whether `body` returns, throws, or is cancelled.
///
/// - Important: iOS callers wrap the call in a background-task assertion so the lock is never held
///   across app suspension, and any refresh HTTP request inside `body` must time out in under 10 s.
///   `body` races `timeout`; on timeout it is cancelled and `.timeout` is thrown. A body that ignores
///   cancellation keeps the lock until it returns.
public struct FileRefreshLock: Sendable {
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "RefreshLock")
    private static let retry: Duration = .milliseconds(50)

    private let url: URL
    private let timeout: Duration

    public init(url: URL, timeout: Duration = .seconds(15)) {
        self.url = url
        self.timeout = timeout
    }

    public func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        let fd = try openLockFile()
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        try await acquire(fd)
        return try await withoutActuallyEscaping(body) { body in
            try await withThrowingTaskGroup(of: T?.self) { group in
                let timeout = self.timeout
                group.addTask { try await body() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let value = first else {
                    Self.log.notice("refresh body exceeded lock timeout")
                    throw FileRefreshLockError.timeout
                }
                return value
            }
        }
    }

    private func acquire(_ fd: Int32) async throws {
        let deadline = ContinuousClock.now + timeout
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let err = errno
            guard err == EWOULDBLOCK || err == EINTR else { throw FileRefreshLockError.open(errno: err) }
            guard ContinuousClock.now < deadline else {
                Self.log.notice("timed out waiting for refresh lock")
                throw FileRefreshLockError.timeout
            }
            try await Task.sleep(for: Self.retry)
        }
    }

    private func openLockFile() throws -> Int32 {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            SnapshotCache.protect(dir)
        }
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw FileRefreshLockError.open(errno: errno) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            close(fd)
            Self.log.error("refresh lock path is not a regular file")
            throw FileRefreshLockError.open(errno: EINVAL)
        }
        fchmod(fd, 0o600)
        SnapshotCache.protect(url)
        return fd
    }
}
