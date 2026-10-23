import Foundation
import Security
import Testing
@testable import UsageCore

/// Pure dictionary checks; never calls SecItem*, so no Keychain items are created.
struct CredentialStoreQueryShapeTests {
    let id = AccountID(kind: .claude, remoteID: "q-test")
    let group = "TEAMID.cc.kuoc.agent-hourglass.shared"
    let groupKey = kSecAttrAccessGroup as String
    let syncKey = kSecAttrSynchronizable as String

    func queries(_ s: CredentialStore) -> [String: [String: Any]] {
        [
            "read": s.readQuery(for: id),
            "update": s.query(for: id),
            "add": s.addQuery(for: id, data: Data("x".utf8), label: "l"),
            "delete": s.query(for: id),
            "list": s.listQuery(),
        ]
    }

    @Test func accessGroupOnEveryQueryWhenSet() {
        for (name, q) in queries(CredentialStore(accessGroup: group)) {
            #expect(q[groupKey] as? String == group, "\(name)")
            #expect(q[syncKey] == nil, "\(name)")
        }
    }

    @Test func noAccessGroupWhenNil() {
        for (name, q) in queries(CredentialStore()) {
            #expect(q[groupKey] == nil, "\(name)")
            #expect(q[syncKey] == nil, "\(name)")
        }
    }

    @Test func writeAttributesThisDeviceOnlyAndNotSynchronizable() {
        let s = CredentialStore(accessGroup: group)
        for a in [s.writeAttributes(data: Data(), label: "l"), s.addQuery(for: id, data: Data(), label: "l")] {
            #expect((a[kSecAttrAccessible as String] as! CFString) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
            #expect(a[syncKey] == nil)
        }
    }

}
