import Foundation

public enum AppSupport {
    public static let folderName = "cc.kuoc.claude-usage"

    /// `<base>/cc.kuoc.claude-usage`, created (or tightened) to 0700. Default base is Application Support.
    public static func directory(base: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let root = try base ?? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = root.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Atomic write, then chmod 0600.
    public static func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
