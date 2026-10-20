import Foundation
import Testing
@testable import UsageCore

struct AccountRegistryTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func entry(_ remote: String, name: String = "Acct") -> AccountEntry {
        AccountEntry(
            id: AccountID(kind: .claude, remoteID: remote),
            kind: .claude,
            displayName: name,
            remoteLogin: "x@example.com",
            order: 0,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: "active"
        )
    }

    func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    @Test func roundTripVersion1() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        #expect(try await reg.load().isEmpty)
        try await reg.upsert(entry("a", name: "Personal"))
        try await reg.upsert(entry("b"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: reg.url)) as! [String: Any]
        #expect(json["version"] as? Int == 1)
        #expect(json["menuBarAccountID"] as? String == "claude:a")
        let fresh = AccountRegistry(directory: dir)
        let loaded = try await fresh.load()
        #expect(loaded == (try await reg.accounts()))
        #expect(loaded.map(\.displayName) == ["Personal", "Acct"])
        #expect(await fresh.menuBarAccountID?.rawValue == "claude:a")
    }

    @Test func upsertSameIdNoDuplicate() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        try await reg.upsert(entry("b"))
        var again = entry("a")
        again.status = "needsLogin"
        try await reg.upsert(again)
        let all = try await reg.accounts()
        #expect(all.count == 2)
        #expect(all[0].id.rawValue == "claude:a" && all[0].order == 0 && all[0].status == "needsLogin")
    }

    @Test func firstAddedIsMenuBarDefault() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        #expect(await reg.menuBarAccountID == nil)
        try await reg.upsert(entry("a"))
        try await reg.upsert(entry("b"))
        #expect(await reg.menuBarAccountID?.rawValue == "claude:a")
        try await reg.setMenuBarAccount(AccountID(kind: .claude, remoteID: "b"))
        #expect(await reg.menuBarAccountID?.rawValue == "claude:b")
        try await reg.remove(AccountID(kind: .claude, remoteID: "b"))
        #expect(await reg.menuBarAccountID?.rawValue == "claude:a")
        try await reg.remove(AccountID(kind: .claude, remoteID: "a"))
        #expect(await reg.menuBarAccountID == nil)
    }

    @Test func reorderWritesOrder() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        for r in ["a", "b", "c"] { try await reg.upsert(entry(r)) }
        try await reg.reorder(["c", "a", "b"].map { AccountID(kind: .claude, remoteID: $0) })
        let loaded = try await AccountRegistry(directory: dir).load()
        #expect(loaded.map(\.id.rawValue) == ["claude:c", "claude:a", "claude:b"])
        #expect(loaded.map(\.order) == [0, 1, 2])
    }

    @Test func corruptFileQuarantined() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("accounts.json")
        try Data("{\"version\":1,\"accou".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let reg = AccountRegistry(directory: dir)
        #expect(try await reg.load().isEmpty)
        #expect(await reg.menuBarAccountID == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let bad = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("accounts.json.bad-") }
        #expect(bad.count == 1)
        #expect(try mode(dir.appendingPathComponent(bad[0])) == 0o600)
        try await reg.upsert(entry("a"))
        #expect(try await AccountRegistry(directory: dir).load().count == 1)
    }

    @Test func emptyRenameRejected() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        let id = AccountID(kind: .claude, remoteID: "a")
        try await reg.upsert(entry("a", name: "Old"))
        await #expect(throws: AccountRegistryError.emptyName) { try await reg.rename(id, to: "   ") }
        #expect(try await AccountRegistry(directory: dir).load()[0].displayName == "Old")
        try await reg.rename(id, to: " New ")
        #expect(try await AccountRegistry(directory: dir).load()[0].displayName == "New")
    }

    @Test func fileMode0600() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        #expect(try mode(reg.url) == 0o600)
    }
}
