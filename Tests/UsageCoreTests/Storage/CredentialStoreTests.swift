import Foundation
import Security
import Testing
@testable import UsageCore

@Suite(.serialized)
final class CredentialStoreTests {
    let store = CredentialStore(service: CredentialStore.service + ".tests")
    let other = CredentialStore(service: CredentialStore.service + ".tests.other")
    let id = AccountID(kind: .claude, remoteID: "test-account")

    func cred(_ token: String) -> Credential {
        Credential(
            kind: .claude,
            access: Secret(token),
            refresh: Secret("ref-\(token)"),
            expiresAt: Date(timeIntervalSince1970: 1_792_537_200),
            refreshExpiresAt: nil,
            scopes: ["user:profile"]
        )
    }

    init() throws {
        try cleanup()
    }

    deinit {
        try? cleanup()
    }

    func cleanup() throws {
        for s in [store, other] {
            for a in try s.allAccountIDs() { try s.delete(a) }
        }
    }

    @Test func writeReadRoundTrip() throws {
        try store.write(cred("tok-1"), for: id, label: "test")
        #expect(try store.read(id) == cred("tok-1"))
        #expect(try store.read(AccountID(kind: .claude, remoteID: "missing")) == nil)
    }

    @Test func updateDoesNotDuplicate() throws {
        try store.write(cred("tok-1"), for: id, label: "test")
        try store.write(cred("tok-2"), for: id, label: "test")
        #expect(try store.allAccountIDs() == [id])
        #expect(try store.read(id)?.access == Secret("tok-2"))
    }

    @Test func deleteOnlyOwnService() throws {
        try store.write(cred("tok-1"), for: id, label: "test")
        try other.write(cred("tok-o"), for: id, label: "test")
        try store.delete(id)
        #expect(try store.read(id) == nil)
        #expect(try other.read(id) == cred("tok-o"))
        try store.delete(id)  // deleting a missing item is not an error
    }

    @Test func inMemoryStoreInjectsWriteError() throws {
        let mem = InMemoryCredentialStore()
        try mem.write(cred("tok-1"), for: id, label: "x")
        #expect(try mem.allAccountIDs() == [id])
        mem.writeError = CredentialStoreError.unexpected(status: -1)
        #expect(throws: CredentialStoreError.self) { try mem.write(cred("tok-2"), for: id, label: "x") }
    }
}

@Suite struct CredentialStoreQueryTests {
    let id = AccountID(kind: .claude, remoteID: "x")

    @Test func macQueryUnchanged() {
        let s = CredentialStore(service: "s")
        let base: Set<String> = [kSecClass as String, kSecAttrService as String]
        #expect(Set(s.query(for: id).keys) == base.union([kSecAttrAccount as String]))
        #expect(Set(s.query(for: nil).keys) == base)
    }

    @Test func accessGroupScopesEveryQuery() {
        let group = "TEAM.cc.kuoc.agent-hourglass.shared"
        let s = CredentialStore(service: "s", accessGroup: group)
        #expect(s.query(for: nil)[kSecAttrAccessGroup as String] as? String == group)
        #expect(s.query(for: id)[kSecAttrAccessGroup as String] as? String == group)
    }

    @Test func defaultsUnchanged() {
        #expect(CredentialStore.service == "cc.kuoc.agent-hourglass")
        #expect(CredentialStore().service == CredentialStore.service)
        #expect(CredentialStore().accessGroup == nil)
    }
}
