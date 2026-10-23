import Foundation
import Security
import Testing
@testable import UsageCore

/// Add-query attributes the phone relies on: shared access group, this-device-only, never synced.
struct CredentialStoreAttributesTests {
    let id = AccountID(kind: .claude, remoteID: "attr-test")

    @Test func addQuery_iOSAccessGroup() {
        let group = "R7V5X99HYA.cc.kuoc.agent-hourglass.shared"
        let q = CredentialStore(service: "cc.kuoc.agent-hourglass", accessGroup: group).addQuery(for: id, data: Data(), label: "l")
        #expect(q[kSecAttrService as String] as? String == "cc.kuoc.agent-hourglass")
        #expect(q[kSecAttrAccessGroup as String] as? String == group)
        #expect((q[kSecAttrAccessible as String] as! CFString) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        #expect(q[kSecAttrSynchronizable as String] == nil)
    }

    @Test func addQuery_macHasNoAccessGroup() {
        let q = CredentialStore().addQuery(for: id, data: Data(), label: "l")
        #expect(q[kSecAttrAccessGroup as String] == nil)
        #expect(q[kSecAttrSynchronizable as String] == nil)
    }
}
