import Foundation
import Testing
@testable import UsageCore

struct LegacyMigrationTests {
    let fm = FileManager.default
    func tmp() -> URL { fm.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func mode(_ url: URL) throws -> Int {
        (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }
    func defaults() -> UserDefaults {
        let name = "lm.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    func cred(_ t: String) -> Credential {
        Credential(kind: .claude, access: Secret(t), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
    }

    @Test func movesDirKeepingModes() throws {
        let base = tmp(); defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent(LegacyMigration.oldID)
        try fm.createDirectory(at: old, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try AppSupport.secureWrite(Data("{}".utf8), to: old.appendingPathComponent("accounts.json"))
        #expect(LegacyMigration.migrateDirectory(base: base) == .moved)
        let new = base.appendingPathComponent(AppSupport.folderName)
        #expect(try mode(new) == 0o700)
        #expect(try mode(new.appendingPathComponent("accounts.json")) == 0o600)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(LegacyMigration.migrateDirectory(base: base) == .noLegacy)
    }

    @Test func keepsBothWhenNewExists() throws {
        let base = tmp(); defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base.appendingPathComponent(LegacyMigration.oldID), withIntermediateDirectories: true)
        _ = try AppSupport.directory(base: base)
        #expect(LegacyMigration.migrateDirectory(base: base) == .alreadyPresent)
        #expect(fm.fileExists(atPath: base.appendingPathComponent(LegacyMigration.oldID).path))
    }

    @Test func defaultsCopyMissingOnce() {
        let d = defaults()
        d.set("glass", forKey: "theme")
        #expect(LegacyMigration.migrateDefaults(old: ["theme": "instrument", "x": 1], target: d) == 1)
        #expect(d.string(forKey: "theme") == "glass")
        #expect(d.integer(forKey: "x") == 1)
        #expect(d.bool(forKey: LegacyMigration.defaultsFlag))
        #expect(LegacyMigration.migrateDefaults(old: ["y": 2], target: d) == 0)
    }

    final class DenyingStore: CredentialStoring, @unchecked Sendable {
        var deleted = false
        func read(_ id: AccountID) throws -> Credential? { throw CredentialStoreError.unexpected(status: -128) }
        func write(_ c: Credential, for id: AccountID, label: String) throws {}
        func delete(_ id: AccountID) throws { deleted = true }
        func allAccountIDs() throws -> [AccountID] { [] }
    }

    @Test func keychainMovesVerifiesDeletes() throws {
        let a = AccountID(kind: .claude, remoteID: "a"), b = AccountID(kind: .claude, remoteID: "b")
        let c = AccountID(kind: .claude, remoteID: "c")
        let old = InMemoryCredentialStore(), new = InMemoryCredentialStore(), d = defaults()
        try old.write(cred("fake-a"), for: a, label: "")
        try new.write(cred("fake-b"), for: b, label: "")
        let r = LegacyMigration.migrateKeychain(ids: [a, b, c], old: old, new: new, label: { _ in "L" }, defaults: d)
        #expect(r.moved == 1 && r.alreadyNew == 1 && r.absent == 1 && r.failed == 0)
        #expect(try new.read(a) == cred("fake-a"))
        #expect(try old.read(a) == nil)
        // Second run is a no-op.
        try old.write(cred("fake-z"), for: c, label: "")
        #expect(LegacyMigration.migrateKeychain(ids: [c], old: old, new: new, label: { _ in "L" }, defaults: d) == .init())
    }

    @Test func keychainNoIDsDoesNotSetFlag() {
        let d = defaults()
        _ = LegacyMigration.migrateKeychain(ids: [], old: InMemoryCredentialStore(), new: InMemoryCredentialStore(), label: { _ in "L" }, defaults: d)
        #expect(!d.bool(forKey: LegacyMigration.keychainFlag))
    }

    @Test func keychainWriteFailureKeepsOld() throws {
        let a = AccountID(kind: .claude, remoteID: "a")
        let old = InMemoryCredentialStore(), new = InMemoryCredentialStore()
        try old.write(cred("fake-a"), for: a, label: "")
        new.writeError = CredentialStoreError.unexpected(status: -1)
        let r = LegacyMigration.migrateKeychain(ids: [a], old: old, new: new, label: { _ in "L" }, defaults: defaults())
        #expect(r.failed == 1)
        #expect(try old.read(a) == cred("fake-a"))
    }

    @Test func keychainDeniedReadLeavesOldAndDoesNotRetry() {
        let a = AccountID(kind: .claude, remoteID: "a")
        let old = DenyingStore(), new = InMemoryCredentialStore(), d = defaults()
        let r = LegacyMigration.migrateKeychain(ids: [a], old: old, new: new, label: { _ in "L" }, defaults: d)
        #expect(r.failed == 1 && !old.deleted)
        #expect(d.bool(forKey: LegacyMigration.keychainFlag))
    }
}
