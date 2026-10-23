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

    @Test func authorizeURLHasNoVerifier() {
        let p = PKCE.make()
        let url = ClaudePKCEFlow().authorizeURL(pkce: p, redirectURI: ClaudePKCEFlow.redirectURI(port: 54321), loginHint: "a@b.c").absoluteString
        #expect(!url.contains(p.verifier.reveal()))
        #expect(url.contains("code_challenge=\(p.challenge)"))
        #expect(url.contains("redirect_uri=http://localhost:54321/callback"))
        #expect(url.contains("login_hint=a@b.c"))
    }

    @Test func codeFragmentStripped() {
        #expect(ClaudePKCEFlow.stripFragment("abc#st") == "abc")
        #expect(ClaudePKCEFlow.stripFragment("abc") == "abc")
    }

    @Test func differentAccountRejected() async throws {
        let flow = ClaudePKCEFlow(exchange: { _, _, _ in
            (Credential(kind: .claude, access: Secret("a"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), "other")
        })
        await #expect(throws: AuthError.differentAccount) {
            _ = try await flow.run(loginHint: nil, open: { url in
                let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                let q = Dictionary(uniqueKeysWithValues: c.queryItems!.map { ($0.name, $0.value!) })
                let cb = URL(string: "\(q["redirect_uri"]!)?code=x%23y&state=\(q["state"]!)")!
                Task { _ = try? await URLSession(configuration: .ephemeral).data(from: cb) }
            }, expectedRemoteID: "mine")
        }
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

    @Test func loopbackRedirectMatchesExchange() async throws {
        let rec = Recorder()
        let authorizeRedirect = Recorder()
        let flow = ClaudePKCEFlow(exchange: { code, _, redirect in
            await rec.record(code, redirect)
            return (Credential(kind: .claude, access: Secret("a"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: []), "id")
        })
        _ = try await flow.run(loginHint: nil, open: { url in
            let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let q = Dictionary(uniqueKeysWithValues: c.queryItems!.map { ($0.name, $0.value!) })
            let redirect = q["redirect_uri"]!
            let cb = URL(string: "\(redirect)?code=x%23y&state=\(q["state"]!)")!
            Task {
                await authorizeRedirect.record("", redirect)
                _ = try? await URLSession(configuration: .ephemeral).data(from: cb)
            }
        })
        let exchanged = await rec.calls.first?.1
        let authorized = await authorizeRedirect.calls.first?.1
        #expect(exchanged != nil)
        #expect(exchanged == authorized)
        #expect(exchanged?.hasPrefix("http://localhost:") == true)
    }
}

private actor Recorder {
    var calls: [(String, String)] = []
    func record(_ code: String, _ redirect: String) { calls.append((code, redirect)) }
}
