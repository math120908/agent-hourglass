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
        "about:blank",
    ])
    func allowedMainFrame(_ s: String) {
        #expect(ElevenLabsWebSession.isAllowedNavigation(URL(string: s)!, isMainFrame: true))
    }

    @Test(arguments: [
        "http://elevenlabs.io/app/sign-in",
        "https://evilelevenlabs.io/",
        "https://elevenlabs.io.evil.com/",
        "https://accounts.google.com/o/oauth2/auth",
        "https://xi-labs.firebaseapp.com/__/auth/handler",
        "https://newassets.hcaptcha.com/captcha/v1/",
        "https://evil.com/",
        "about:srcdoc",
        "javascript:alert(1)",
        "file:///etc/passwd",
    ])
    func refusedMainFrame(_ s: String) {
        #expect(!ElevenLabsWebSession.isAllowedNavigation(URL(string: s)!, isMainFrame: true))
    }

    @Test(arguments: [
        "https://newassets.hcaptcha.com/captcha/v1/",
        "https://challenges.cloudflare.com/turnstile/v0/",
        "https://elevenlabs.io/app/sign-in",
        "about:blank",
    ])
    func allowedSubframe(_ s: String) {
        #expect(ElevenLabsWebSession.isAllowedNavigation(URL(string: s)!, isMainFrame: false))
    }

    @Test(arguments: [
        "http://newassets.hcaptcha.com/captcha/v1/",
        "about:srcdoc",
        "javascript:alert(1)",
        "file:///etc/passwd",
    ])
    func refusedSubframe(_ s: String) {
        #expect(!ElevenLabsWebSession.isAllowedNavigation(URL(string: s)!, isMainFrame: false))
    }
}
