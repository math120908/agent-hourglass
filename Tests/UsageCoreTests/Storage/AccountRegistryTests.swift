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
        #expect(loaded == (await reg.accounts()))
        #expect(loaded.map(\.displayName) == ["Personal", "Acct"])
        #expect(await fresh.menuBarAccountID?.rawValue == "claude:a")
    }

    @Test func setStatusPersistsAndSkipsNoOp() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        try await reg.setStatus(AccountID(rawValue: "claude:a")!, "needsLogin")
        #expect(try await AccountRegistry(directory: dir).load().first?.status == "needsLogin")
        await #expect(throws: AccountRegistryError.self) { try await reg.setStatus(AccountID(rawValue: "claude:zz")!, "ok") }
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
        let all = await reg.accounts()
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

    // A registry that treats codex as a new kind stands in for google/grok (not yet in ProviderKind).
    func extRegistry() -> AccountRegistry { AccountRegistry(directory: dir, isMain: { $0 != .codex }) }

    func codex(_ remote: String) -> AccountEntry {
        AccountEntry(
            id: AccountID(kind: .codex, remoteID: remote),
            kind: .codex,
            displayName: "Codex",
            remoteLogin: nil,
            order: 0,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: "active"
        )
    }

    func json(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(name))) as! [String: Any]
    }

    func ids(_ file: [String: Any]) -> [String] {
        (file["accounts"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    @Test func newKindGoesToExtFile() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = extRegistry()
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        try await reg.upsert(codex("x"))
        #expect(ids(try json(AccountRegistry.fileName)) == ["claude:a"])
        #expect(ids(try json(AccountRegistry.extFileName)) == ["codex:x"])
        #expect(try mode(reg.url) == 0o600)
        #expect(try mode(reg.extURL) == 0o600)
    }

    @Test func mergedOrderSurvivesReload() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = extRegistry()
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        try await reg.upsert(codex("x"))
        try await reg.reorder([AccountID(kind: .codex, remoteID: "x"), AccountID(kind: .claude, remoteID: "a")])
        #expect(try await extRegistry().load().map(\.id.rawValue) == ["codex:x", "claude:a"])
    }

    @Test func menuBarExtIDStaysInMainFile() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = extRegistry()
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        try await reg.upsert(codex("x"))
        let x = AccountID(kind: .codex, remoteID: "x")
        try await reg.setMenuBarAccount(x)
        #expect(try json(AccountRegistry.fileName)["menuBarAccountID"] as? String == "codex:x")
        #expect(try json(AccountRegistry.extFileName)["menuBarAccountID"] == nil)
        let fresh = extRegistry()
        _ = try await fresh.load()
        #expect(await fresh.menuBarAccountID == x)
    }

    @Test func unknownExtEntryPreservedOnWrite() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let future: [String: Any] = [
            "id": "future:z", "kind": "future", "displayName": "Future", "order": 0,
            "addedAt": "2023-11-14T22:13:20Z", "status": "active", "extra": ["nested": 1],
        ]
        let valid = try JSONSerialization.jsonObject(with: JSONEncoder.iso.encode(codex("x"))) as! [String: Any]
        let seed: [String: Any] = ["version": 1, "accounts": [valid, future]]
        try JSONSerialization.data(withJSONObject: seed).write(to: dir.appendingPathComponent(AccountRegistry.extFileName))
        let reg = extRegistry()
        #expect(try await reg.load().map(\.id.rawValue) == ["codex:x"])
        #expect(await reg.accounts().map(\.id.rawValue) == ["codex:x"])
        #expect(await reg.loadedCleanly)
        try await reg.upsert(codex("y"))
        let written = try json(AccountRegistry.extFileName)["accounts"] as! [[String: Any]]
        #expect(written.map { $0["id"] as! String }.sorted() == ["codex:x", "codex:y", "future:z"])
        let kept = try #require(written.first { $0["id"] as? String == "future:z" })
        #expect(NSDictionary(dictionary: kept).isEqual(to: future))
    }

    @Test func corruptExtFileQuarantinesOnlyExt() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = extRegistry()
        _ = try await reg.load()
        try await reg.upsert(entry("a"))
        try Data("not json".utf8).write(to: reg.extURL)
        let fresh = extRegistry()
        #expect(try await fresh.load().map(\.id.rawValue) == ["claude:a"])
        #expect(await !fresh.loadedCleanly)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("\(AccountRegistry.extFileName).bad-") })
        #expect(!names.contains { $0.hasPrefix("\(AccountRegistry.fileName).bad-") })
        #expect(names.contains(AccountRegistry.fileName))
        #expect(await fresh.menuBarAccountID?.rawValue == "claude:a")
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
