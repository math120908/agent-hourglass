import Foundation
import Testing
@testable import UsageCore

struct RedactionTests {
    let raw = "tok-AAAA1234"

    var cred: Credential {
        Credential(
            kind: .claude,
            access: Secret(raw),
            refresh: Secret("ref-BBBB5678"),
            expiresAt: Date(timeIntervalSince1970: 1_792_537_200),
            refreshExpiresAt: nil,
            scopes: ["user:profile"]
        )
    }

    @Test func describingRedacts() {
        #expect(!String(describing: cred).contains(raw))
        #expect(!String(describing: cred.access).contains(raw))
        #expect(String(describing: cred.access) == "Secret(<redacted>)")
    }

    @Test func reflectingRedacts() {
        #expect(!String(reflecting: cred).contains(raw))
        #expect(!String(reflecting: cred.access).contains(raw))
    }

    @Test func dumpRedacts() {
        var out = ""
        dump(cred, to: &out)
        #expect(!out.contains(raw))
        #expect(!out.contains("ref-BBBB5678"))
        var out2 = ""
        dump(cred.access, to: &out2)
        #expect(!out2.contains(raw))
    }

    @Test func interpolationRedacts() {
        #expect(!"\(cred)".contains(raw))
        #expect(!"\(cred.access)".contains(raw))
        #expect("\(cred)" == "Credential(claude, expires 2026-10-20T23:00:00Z)")
    }

    @Test func jsonRoundTrip() throws {
        let data = try JSONEncoder().encode(cred)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(Set(obj.keys).isSuperset(of: ["access", "refresh", "expiresAt", "scopes"]))
        let back = try JSONDecoder().decode(Credential.self, from: data)
        #expect(back == cred)
        #expect(back.access.reveal() == raw)
    }
}
