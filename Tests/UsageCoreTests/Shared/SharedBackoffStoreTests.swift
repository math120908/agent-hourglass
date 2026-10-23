import Foundation
import Testing
@testable import UsageCore

struct SharedBackoffStoreTests {
    let dir: URL
    let store: SharedBackoffStore
    let a = AccountID(kind: .claude, remoteID: "acct-a")
    let b = AccountID(kind: .claude, remoteID: "acct-b")

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = SharedBackoffStore(directory: dir)
    }

    func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    func close(_ x: Date?, _ y: Date) -> Bool {
        guard let x else { return false }
        return abs(x.timeIntervalSince1970 - y.timeIntervalSince1970) < 0.001
    }

    @Test func unsetIsNil() {
        #expect(store.nextAllowedFetch(a) == nil)
    }

    @Test func setThenGet() throws {
        let d = Date().addingTimeInterval(120.123)
        try store.setNextAllowedFetch(d, for: a)
        #expect(close(store.nextAllowedFetch(a), d))
    }

    @Test func laterWriteWins() throws {
        let d1 = Date().addingTimeInterval(600), d2 = Date().addingTimeInterval(60)
        try store.setNextAllowedFetch(d1, for: a)
        try store.setNextAllowedFetch(d2, for: a)
        #expect(close(store.nextAllowedFetch(a), d2))
    }

    @Test func perAccountIsolation() throws {
        try store.setNextAllowedFetch(Date().addingTimeInterval(60), for: a)
        #expect(store.nextAllowedFetch(b) == nil)
    }

    @Test(arguments: ["garbage", "{\"nextAllowedFetch\":", "{\"other\":1}", ""])
    func corruptFileMeansNoGate(_ contents: String) throws {
        try store.setNextAllowedFetch(Date().addingTimeInterval(60), for: a)
        try Data(contents.utf8).write(to: store.url(for: a))
        #expect(store.nextAllowedFetch(a) == nil)
    }

    @Test func twoInstancesSameDirectoryShare() throws {
        let d = Date().addingTimeInterval(300)
        try store.setNextAllowedFetch(d, for: a)
        #expect(close(SharedBackoffStore(directory: dir).nextAllowedFetch(a), d))
    }

    @Test func farFutureIsClampedToOneHour() throws {
        let now = Date()
        try store.setNextAllowedFetch(now.addingTimeInterval(365 * 86400), for: a)
        #expect(close(store.nextAllowedFetch(a, now: now), now.addingTimeInterval(3600)))
        let live = try #require(store.nextAllowedFetch(a))
        #expect(live <= Date().addingTimeInterval(3600))
    }

    @Test func fileModes() throws {
        try store.setNextAllowedFetch(Date(), for: a)
        #expect(try mode(dir.appendingPathComponent("backoff")) == 0o700)
        #expect(try mode(store.url(for: a)) == 0o600)
    }
}
