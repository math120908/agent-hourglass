import Foundation
import Testing
@testable import UsageCore

struct ElevenLabsWebSessionTests {
    let user = #"{"uid":"fake-uid","email":"a@example.com","stsTokenManager":{"refreshToken":"fake-rt","accessToken":"fake-at","expirationTime":1}}"#

    @Test func parsesStringEncodedUser() throws {
        let json = String(data: try JSONSerialization.data(withJSONObject: [user]), encoding: .utf8)!
        let s = try #require(ElevenLabsWebSession.parse(json))
        #expect(s.uid == "fake-uid")
        #expect(s.email == "a@example.com")
        #expect(s.refreshToken.reveal() == "fake-rt")
    }

    @Test func parsesObjectUserFromIndexedDB() throws {
        let s = try #require(ElevenLabsWebSession.parse("[\(user)]"))
        #expect(s.uid == "fake-uid")
    }

    @Test func skipsIncompleteEntries() throws {
        let noToken = #"{"uid":"x","stsTokenManager":{}}"#
        let s = try #require(ElevenLabsWebSession.parse("[\(noToken),\(user)]"))
        #expect(s.uid == "fake-uid")
    }

    @Test func emptyOrGarbageIsNil() {
        #expect(ElevenLabsWebSession.parse("[]") == nil)
        #expect(ElevenLabsWebSession.parse("not json") == nil)
        #expect(ElevenLabsWebSession.parse(#"[{"uid":"","stsTokenManager":{"refreshToken":"r"}}]"#) == nil)
    }

    @Test func missingEmailIsNil() throws {
        let s = try #require(ElevenLabsWebSession.parse(#"[{"uid":"u","email":"","stsTokenManager":{"refreshToken":"r"}}]"#))
        #expect(s.email == nil)
    }

    @Test func seedCredentialCarriesRefreshAndIdentity() throws {
        let c = try #require(ElevenLabsWebSession.parse("[\(user)]")).seedCredential
        #expect(c.kind == .elevenlabs)
        #expect(c.refresh?.reveal() == "fake-rt")
        #expect(c.remoteAccountID == "fake-uid")
        #expect(c.accountEmail == "a@example.com")
        #expect(!c.description.contains("fake-rt"))
    }
}

struct ElevenLabsWebSessionHostTests {
    @Test func probeHost() {
        #expect(ElevenLabsWebSession.isProbeHost("elevenlabs.io"))
        #expect(ElevenLabsWebSession.isProbeHost("ElevenLabs.IO"))
        #expect(ElevenLabsWebSession.isProbeHost("app.elevenlabs.io"))
        #expect(!ElevenLabsWebSession.isProbeHost("evilelevenlabs.io"))
        #expect(!ElevenLabsWebSession.isProbeHost("elevenlabs.io.evil.com"))
        #expect(!ElevenLabsWebSession.isProbeHost(nil))
    }

    @Test(arguments: [
        "https://elevenlabs.io/app/sign-in",
        "https://api.elevenlabs.io/x",
        "https://accounts.google.com/o/oauth2/auth",
        "https://xi-labs.firebaseapp.com/__/auth/handler",
        "about:blank",
    ])
    func allowed(_ s: String) {
        #expect(ElevenLabsWebSession.isAllowedNavigation(URL(string: s)!))
    }

    @Test(arguments: [
        "http://elevenlabs.io/app/sign-in",
        "https://evilelevenlabs.io/",
        "https://elevenlabs.io.evil.com/",
        "http://accounts.google.com/",
        "https://evil.com/",
        "https://xi-labs.firebaseapp.com/other",
        "https://firebaseapp.com/__/auth/handler",
        "about:srcdoc",
        "javascript:alert(1)",
        "file:///etc/passwd",
    ])
    func refused(_ s: String) {
        #expect(!ElevenLabsWebSession.isAllowedNavigation(URL(string: s)!))
    }
}
