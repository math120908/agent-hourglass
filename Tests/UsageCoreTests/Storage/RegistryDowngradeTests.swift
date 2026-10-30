import Foundation
import Testing
@testable import UsageCore

/// Private copy of the shipped v1.0.20 `accounts.json` decoder (`Sources/UsageCore/Storage/AccountRegistry.swift`
/// and `ProviderKind.swift` at `origin/master` 80b7ffd). Shipped builds decode all-or-nothing and quarantine on any
/// unknown kind, so `accounts.json` must stay decodable by this copy.
private enum V1020Kind: String, Decodable { case claude, copilot, codex }

private struct V1020Entry: Decodable {
    var id: AccountID
    var kind: V1020Kind
    var displayName: String
    var remoteLogin: String?
    var order: Int
    var addedAt: Date
    var status: String
    var nameIsCustom: Bool

    enum CodingKeys: String, CodingKey { case id, kind, displayName, remoteLogin, order, addedAt, status, nameIsCustom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(AccountID.self, forKey: .id)
        kind = try c.decode(V1020Kind.self, forKey: .kind)
        displayName = try c.decode(String.self, forKey: .displayName)
        remoteLogin = try c.decodeIfPresent(String.self, forKey: .remoteLogin)
        order = try c.decode(Int.self, forKey: .order)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        status = try c.decode(String.self, forKey: .status)
        nameIsCustom = try c.decodeIfPresent(Bool.self, forKey: .nameIsCustom) ?? false
    }
}

private struct V1020File: Decodable {
    var version: Int
    var menuBarAccountID: AccountID?
    var accounts: [V1020Entry]
}

private func v1020Decode(_ url: URL) throws -> V1020File {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    let file = try d.decode(V1020File.self, from: Data(contentsOf: url))
    guard file.version == 1 else { throw AccountRegistryError.unsupportedVersion(file.version) }
    return file
}

struct RegistryDowngradeTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("downgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func entry(_ kind: ProviderKind, _ remote: String) -> AccountEntry {
        AccountEntry(
            id: AccountID(kind: kind, remoteID: remote),
            kind: kind,
            displayName: "Acct",
            remoteLogin: nil,
            order: 0,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: "active"
        )
    }

    @Test func downgradeSafeWithLegacyKindsOnly() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        try await reg.upsert(entry(.claude, "a"))
        try await reg.upsert(entry(.codex, "x"))
        let file = try v1020Decode(reg.url)
        #expect(file.accounts.map(\.id.rawValue) == ["claude:a", "codex:x"])
        #expect(!FileManager.default.fileExists(atPath: reg.extURL.path))
    }

    @Test func downgradeSafeWithGrokAccount() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = AccountRegistry(directory: dir)
        _ = try await reg.load()
        try await reg.upsert(entry(.claude, "a"))
        try await reg.upsert(entry(.grok, "sub-1"))
        try await reg.setMenuBarAccount(AccountID(kind: .grok, remoteID: "sub-1"))
        let file = try v1020Decode(reg.url)
        #expect(file.accounts.map(\.id.rawValue) == ["claude:a"])
        let ext = try JSONSerialization.jsonObject(with: Data(contentsOf: reg.extURL)) as? [String: Any]
        let extIDs = (ext?["accounts"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        #expect(extIDs == ["grok:sub-1"])
    }
}
