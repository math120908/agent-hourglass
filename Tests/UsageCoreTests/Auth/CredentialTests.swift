import Foundation
import Testing
@testable import UsageCore

struct CredentialTests {
    @Test func decodesLegacyJSONWithoutRemoteAccountID() throws {
        let legacy = #"{"kind":"claude","access":"a","refresh":"r","scopes":[]}"#
        let c = try JSONDecoder().decode(Credential.self, from: Data(legacy.utf8))
        #expect(c.remoteAccountID == nil && c.access == Secret("a"))
    }

    @Test func roundTripsRemoteAccountID() throws {
        let c = Credential(kind: .codex, access: Secret("a"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [], remoteAccountID: "acct-1")
        #expect(try JSONDecoder().decode(Credential.self, from: JSONEncoder().encode(c)) == c)
    }

    @Test func remoteAccountIDNotInDescriptionOrMirror() {
        let c = Credential(kind: .codex, access: Secret("tok"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [], remoteAccountID: "acct-secret-ish")
        #expect(!"\(c)".contains("acct-secret-ish"))
        #expect(!String(reflecting: c).contains("acct-secret-ish"))
        #expect(Mirror(reflecting: c).children.allSatisfy { $0.label != "remoteAccountID" })
    }
}
