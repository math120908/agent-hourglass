import Foundation

/// Last-known `UsageSnapshot` per account at `<directory>/snapshots/<SharedFileName>.json`,
/// shared by the iOS app and widget. Directory 0700, files 0600, no in-memory caching.
public struct SnapshotCache: Sendable {
    private let snapshots: URL

    public init(directory: URL) {
        snapshots = directory.appendingPathComponent("snapshots", isDirectory: true)
    }

    func url(for id: AccountID) -> URL {
        snapshots.appendingPathComponent(SharedFileName.forAccount(id) + ".json", isDirectory: false)
    }

    public func read(_ id: AccountID) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url(for: id)),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data),
              snapshot.accountID == id
        else { return nil }
        return snapshot
    }

    public func write(_ s: UsageSnapshot) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: snapshots, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: snapshots.path)
        Self.protect(snapshots)
        let target = url(for: s.accountID)
        try AppSupport.secureWrite(JSONEncoder().encode(s), to: target)
        Self.protect(target)
    }

    public func remove(_ id: AccountID) throws {
        guard unlink(url(for: id).path) == 0 || errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Widgets read while the phone is locked, so never `.complete`. No-op on macOS.
    static func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
