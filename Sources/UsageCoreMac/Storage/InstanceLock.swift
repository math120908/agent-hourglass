import UsageCore
import Foundation

/// Single-instance guard: an exclusive, non-blocking `flock` on `instance.lock`, held until deinit.
/// flock is per open file description, so a second `acquire` (new fd, same or other process) fails.
public final class InstanceLock: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case alreadyRunning
        case io(Int32)
    }

    public static let fileName = "instance.lock"

    public let url: URL
    private let fd: Int32

    private init(url: URL, fd: Int32) {
        self.url = url
        self.fd = fd
    }

    /// Locks `<AppSupport dir>/instance.lock`. Pass `base` only in tests.
    public static func acquire(in directory: URL? = nil) throws -> InstanceLock {
        let dir = try directory ?? AppSupport.directory()
        return try acquire(at: dir.appendingPathComponent(fileName))
    }

    public static func acquire(at url: URL) throws -> InstanceLock {
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Error.io(errno) }
        guard fchmod(fd, 0o600) == 0 else {
            let e = errno
            close(fd)
            throw Error.io(e)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let e = errno
            close(fd)
            throw e == EWOULDBLOCK ? Error.alreadyRunning : Error.io(e)
        }
        return InstanceLock(url: url, fd: fd)
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
