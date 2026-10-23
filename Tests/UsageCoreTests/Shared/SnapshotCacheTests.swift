import Foundation
import Testing
@testable import UsageCore

struct SnapshotCacheTests {
    let dir: URL
    let cache: SnapshotCache

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cache = SnapshotCache(directory: dir)
    }

    func snap(_ remote: String = "acct", at t: Double = 1_700_000_000.123) -> UsageSnapshot {
        UsageSnapshot(accountID: AccountID(kind: .claude, remoteID: remote), fetchedAt: Date(timeIntervalSince1970: t), plan: "pro", meters: [])
    }

    func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    @Test func writeThenReadRoundTrips() throws {
        let s = snap()
        try cache.write(s)
        #expect(cache.read(s.accountID) == s)
    }

    @Test func readMissingIsNil() {
        #expect(cache.read(AccountID(kind: .claude, remoteID: "nope")) == nil)
    }

    @Test func removeDeletesAndMissingRemoveIsNoError() throws {
        let s = snap()
        try cache.write(s)
        try cache.remove(s.accountID)
        #expect(cache.read(s.accountID) == nil)
        try cache.remove(s.accountID)
    }

    @Test func filesAre0600InDir0700() throws {
        let s = snap()
        try cache.write(s)
        #expect(try mode(dir.appendingPathComponent("snapshots")) == 0o700)
        #expect(try mode(cache.url(for: s.accountID)) == 0o600)
    }

    @Test func corruptOrForeignFileReadsNil() throws {
        let a = snap("A"), b = snap("B")
        try cache.write(a)
        try Data("garbage".utf8).write(to: cache.url(for: a.accountID))
        #expect(cache.read(a.accountID) == nil)
        try JSONEncoder().encode(b).write(to: cache.url(for: a.accountID))
        #expect(cache.read(a.accountID) == nil)
    }

    @Test func hostileRemoteIDsStayInsideDirectory() throws {
        let snapshots = dir.appendingPathComponent("snapshots").standardizedFileURL.path
        for remote in ["../../x", "a/b", ".hidden", String(repeating: "z", count: 300), "ü:é"] {
            let s = snap(remote)
            try cache.write(s)
            let url = cache.url(for: s.accountID)
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == snapshots)
            #expect(cache.read(s.accountID) == s)
        }
        #expect(cache.url(for: snap("a/b").accountID) != cache.url(for: snap("a_b").accountID))
    }

    @Test func fileNameIsHexDigestWithoutRawID() {
        let id = AccountID(kind: .claude, remoteID: "../secret-account@example.com")
        let name = SharedFileName.forAccount(id)
        #expect(name.count == 64)
        #expect(name.allSatisfy { "0123456789abcdef".contains($0) })
        for part in ["claude", "secret", "example", "..", "/"] { #expect(!name.contains(part)) }
    }

    @Test func concurrentWritersNeverLeavePartialFile() async throws {
        let id = snap().accountID
        try cache.write(snap())
        let cache = self.cache
        try await withThrowingTaskGroup(of: Void.self) { group in
            for w in 0..<2 {
                group.addTask {
                    for i in 0..<50 {
                        try cache.write(UsageSnapshot(accountID: id, fetchedAt: Date(timeIntervalSince1970: Double(w * 100 + i)), meters: []))
                        #expect(cache.read(id) != nil)
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(cache.read(id) != nil)
    }
}
