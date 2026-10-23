import Foundation
import Testing
@testable import UsageCore

struct PKCETests {
    @Test func challengeMatchesRFC7636() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func makeProducesUnpaddedBase64url() {
        let p = PKCE.make()
        #expect(p.verifier.reveal().count == 43)
        #expect(p.state.count == 43)
        #expect(!p.challenge.contains("=") && !p.challenge.contains("+") && !p.challenge.contains("/"))
        #expect(PKCE.make().state != p.state)
    }


    @Test func codeFragmentStripped() {
        #expect(ClaudePKCEFlow.stripFragment("abc#st") == "abc")
        #expect(ClaudePKCEFlow.stripFragment("abc") == "abc")
    }


    @Test func manualRedirectAuthorizeURL() {
        let p = PKCE.make()
        let url = ClaudePKCEFlow().authorizeURL(pkce: p, redirectURI: ClaudePKCEFlow.manualRedirectURI, loginHint: nil).absoluteString
        #expect(url.contains("redirect_uri=https://platform.claude.com/oauth/code/callback"))
        #expect(url.contains("client_id=\(ClaudeOAuth.clientID)"))
        #expect(url.contains("scope=user:profile"))
        #expect(!url.contains("login_hint"))
        #expect(url.hasPrefix(ClaudeOAuth.authorizeURL.absoluteString + "?"))
    }

    @Test func exchangePassesRedirectThrough() async throws {
        let rec = Recorder()
        let flow = ClaudePKCEFlow(exchange: { code, _, redirect in
            await rec.record(code, redirect)
            return (Credential(kind: .claude, access: Secret("a"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), "id")
        })
        _ = try await flow.exchange(code: "c", pkce: PKCE.make(), redirectURI: ClaudePKCEFlow.manualRedirectURI)
        let calls = await rec.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "c")
        #expect(calls.first?.1 == "https://platform.claude.com/oauth/code/callback")
    }

}

private actor Recorder {
    var calls: [(String, String)] = []
    func record(_ code: String, _ redirect: String) { calls.append((code, redirect)) }
}
