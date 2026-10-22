import Foundation

public enum AppSupport {
    public static let folderName = "cc.kuoc.agent-hourglass"

    /// `<base>/cc.kuoc.agent-hourglass`, created (or tightened) to 0700. Default base is Application Support.
    public static func directory(base: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let root = try base ?? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = root.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Atomic replace that never exposes umask perms: temp file is created 0600 with O_EXCL in the
    /// target's directory, fsynced, then rename()d over the target.
    public static func secureWrite(_ data: Data, to url: URL) throws {
        try secureWrite(data, to: url, beforeRename: { _ in })
    }

    static func secureWrite(_ data: Data, to url: URL, beforeRename: (URL) throws -> Void) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(tmp.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var renamed = false
        defer { if !renamed { unlink(tmp.path) } }
        do {
            defer { close(fd) }
            // umask can only clear bits; force exact 0600 regardless.
            guard fchmod(fd, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try data.withUnsafeBytes { buf in
                var off = 0
                while off < buf.count {
                    let n = write(fd, buf.baseAddress! + off, buf.count - off)
                    if n < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    off += n
                }
            }
            guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        try beforeRename(tmp)
        guard rename(tmp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        renamed = true
    }
}
