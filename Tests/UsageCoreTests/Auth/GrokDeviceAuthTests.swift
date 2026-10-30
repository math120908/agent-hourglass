import Foundation
import Testing
@testable import UsageCore

// Synthesized from R10 §1 (RFC 8628 device code at auth.x.ai, pullfrog utils/xaiOAuth.ts); no live payload.
struct GrokDeviceAuthTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = CodexTestBox(t0)
    let sleeps = CodexTestBox<[Duration]>([])

    static let start = (200, #"{"device_code":"DEVICE-SENTINEL","user_code":"WXYZ-1234","verification_uri":"https://x.ai/device","verification_uri_complete":"https://accounts.x.ai/device?user_code=WXYZ-1234","interval":5,"expires_in":1800}"#, [String: String]())
    static let tokens = (200, #"{"access_token":"ACCESS-SENTINEL","refresh_token":"REFRESH-SENTINEL","expires_in":3600,"token_type":"Bearer"}"#, [String: String]())
    static func oauthError(_ code: String) -> (Int, String, [String: String]) { (400, "{\"error\":\"\(code)\"}", [:]) }
    static let pending = oauthError("authorization_pending")
    static let userinfo = (200, #"{"sub":"acct-synthetic","email":"grok@example.com","name":"Synthetic"}"#, [String: String]())

    func auth(_ t: ScriptedTransport, advance: TimeInterval = 0) -> GrokDeviceAuth {
        let clock = clock, sleeps = sleeps
        return GrokDeviceAuth(
            http: HTTPClient(transport: t),
            sleep: { d in sleeps.value.append(d); clock.value = clock.value.addingTimeInterval(advance) },
            now: { clock.value },
            monotonic: { ContinuousClock.now }
        )
    }

    func prompt(expiresAt: Date? = nil) -> DeviceCodePrompt {
        DeviceCodePrompt(
            userCode: "WXYZ-1234",
            verificationURL: URL(string: "https://accounts.x.ai/device")!,
            interval: .seconds(5),
            expiresAt: expiresAt ?? Self.t0.addingTimeInterval(900),
            deviceCode: Secret("DEVICE-SENTINEL")
        )
    }

    @Test func startParsesPrompt() async throws {
        let t = ScriptedTransport([Self.start])
        let p = try await auth(t).start()
        try #require(t.requests.count == 1)
        #expect(t.requests[0].url?.absoluteString == "https://auth.x.ai/oauth2/device/code")
        #expect(t.requests[0].httpMethod == "POST")
        #expect(t.requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(t.bodyForm(0) == [
            "client_id": "b1a00492-073a-47ea-816f-4c329264a828",
            "scope": "openid profile email offline_access grok-cli:access api:access",
        ])
        #expect(p.userCode == "WXYZ-1234")
        #expect(p.verificationURL.host() == "accounts.x.ai")
        #expect(p.interval == .seconds(5))
        #expect(p.expiresAt == Self.t0.addingTimeInterval(900))
        #expect(p.deviceCode.reveal() == "DEVICE-SENTINEL")
    }

    @Test func startRejectsForeignVerificationHost() async throws {
        let t = ScriptedTransport([(200, #"{"device_code":"D","user_code":"U","verification_uri":"https://evil.example/device","expires_in":120}"#, [:])])
        let p = try await auth(t).start()
        #expect(p.verificationURL == GrokDeviceAuth.fallbackVerificationURL)
        #expect(p.interval == .seconds(5))
        #expect(p.expiresAt == Self.t0.addingTimeInterval(120))
    }

    @Test func pendingThenSuccess() async throws {
        let t = ScriptedTransport([Self.pending, Self.pending, Self.tokens, Self.userinfo])
        let c = try await auth(t).poll(prompt())
        #expect(sleeps.value == [.seconds(5), .seconds(5)])
        try #require(t.requests.count == 4)
        #expect(t.requests[0].url?.absoluteString == "https://auth.x.ai/oauth2/token")
        #expect(t.bodyForm(0) == [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": "DEVICE-SENTINEL",
            "client_id": "b1a00492-073a-47ea-816f-4c329264a828",
        ])
        #expect(c.kind == .grok)
        #expect(c.access.reveal() == "ACCESS-SENTINEL")
        #expect(c.refresh?.reveal() == "REFRESH-SENTINEL")
    }

    @Test func slowDownWidensInterval() async throws {
        let t = ScriptedTransport([Self.pending, Self.oauthError("slow_down"), Self.tokens, Self.userinfo])
        _ = try await auth(t).poll(prompt())
        #expect(sleeps.value == [.seconds(5), .seconds(10)])
    }

    @Test func deniedStopsImmediately() async throws {
        let t = ScriptedTransport([Self.oauthError("access_denied")])
        await #expect(throws: DeviceFlowError.denied) { try await auth(t).poll(prompt()) }
        #expect(t.requests.count == 1)
        #expect(sleeps.value.isEmpty)
    }

    @Test func expiredStopsImmediately() async throws {
        let t = ScriptedTransport([Self.oauthError("expired_token")])
        await #expect(throws: DeviceFlowError.expired) { try await auth(t).poll(prompt()) }
        #expect(t.requests.count == 1)
        #expect(sleeps.value.isEmpty)
    }

    @Test func deadlineExpires() async throws {
        let t = ScriptedTransport([Self.pending, Self.pending])
        await #expect(throws: DeviceFlowError.expired) { try await auth(t, advance: 600).poll(prompt()) }
        #expect(t.requests.count == 2)
    }

    @Test func unknownErrorAndUnauthorizedAreUnexpected() async throws {
        let t = ScriptedTransport([Self.oauthError("invalid_client")])
        await #expect(throws: DeviceFlowError.unexpected(status: 400)) { try await auth(t).poll(prompt()) }
        let t2 = ScriptedTransport([(401, #"{"error":"invalid_client"}"#, [:])])
        await #expect(throws: DeviceFlowError.unexpected(status: 401)) { try await auth(t2).poll(prompt()) }
        #expect(sleeps.value.isEmpty)
    }

    @Test func tokenWithIDTokenSetsIdentity() async throws {
        let id = CodexDeviceAuthTests.jwt(#"{"sub":"acct-synthetic","email":"grok@example.com"}"#)
        let access = CodexDeviceAuthTests.jwt(#"{"exp":1800003600}"#)
        let body = "{\"access_token\":\"\(access)\",\"refresh_token\":\"REFRESH-SENTINEL\",\"id_token\":\"\(id)\"}"
        let t = ScriptedTransport([(200, body, [:])])
        let c = try await auth(t).poll(prompt())
        #expect(t.requests.count == 1)
        #expect(c.kind == .grok)
        #expect(c.remoteAccountID == "acct-synthetic")
        #expect(c.accountEmail == "grok@example.com")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
    }

    @Test func tokenWithoutIDTokenCallsUserinfo() async throws {
        let t = ScriptedTransport([Self.tokens, Self.userinfo])
        let c = try await auth(t).poll(prompt())
        try #require(t.requests.count == 2)
        let r = t.requests[1]
        #expect(r.url?.absoluteString == "https://auth.x.ai/oauth2/userinfo")
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer ACCESS-SENTINEL")
        #expect(c.remoteAccountID == "acct-synthetic")
        #expect(c.accountEmail == "grok@example.com")
        #expect(c.expiresAt == Self.t0.addingTimeInterval(3600))
    }

    @Test func userinfoWithoutSubIsSchema() async throws {
        let t = ScriptedTransport([Self.tokens, (200, #"{"email":"grok@example.com"}"#, [:])])
        await #expect(throws: ProviderError.schema(keys: ["sub"])) { try await auth(t).poll(prompt()) }
    }

    /// The device code is spent once tokens arrive: a userinfo failure ends the login, never re-polls.
    @Test func userinfoFailureStopsPolling() async throws {
        let t = ScriptedTransport([Self.tokens, (500, "", [:])])
        await #expect(throws: ProviderError.http(status: 500, host: "auth.x.ai", retryAfter: nil)) { try await auth(t).poll(prompt()) }
        #expect(t.requests.count == 2)
        #expect(sleeps.value.isEmpty)
    }

    static func cred(refresh: String? = "OLD-REFRESH-SENTINEL") -> Credential {
        Credential(kind: .grok, access: Secret("OLD-ACCESS"), refresh: refresh.map(Secret.init), expiresAt: t0, refreshExpiresAt: nil, scopes: [], remoteAccountID: "acct-synthetic", accountEmail: "grok@example.com")
    }

    @Test func refreshRotates() async throws {
        let t = ScriptedTransport([(200, #"{"access_token":"NEW-ACCESS","refresh_token":"NEW-REFRESH","expires_in":3600}"#, [:])])
        let c = try await auth(t).refresh(Self.cred())
        try #require(t.requests.count == 1)
        let r = t.requests[0]
        #expect(r.url?.absoluteString == "https://auth.x.ai/oauth2/token")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(t.bodyForm(0) == [
            "grant_type": "refresh_token",
            "refresh_token": "OLD-REFRESH-SENTINEL",
            "client_id": "b1a00492-073a-47ea-816f-4c329264a828",
        ])
        #expect(c.access == Secret("NEW-ACCESS"))
        #expect(c.refresh == Secret("NEW-REFRESH"))
        #expect(c.expiresAt == Self.t0.addingTimeInterval(3600))
        #expect(c.remoteAccountID == "acct-synthetic")
        #expect(c.accountEmail == "grok@example.com")
    }

    @Test func refreshKeepsPreviousWhenNotRotated() async throws {
        let t = ScriptedTransport([(200, #"{"access_token":"NEW-ACCESS","expires_in":3600}"#, [:])])
        let c = try await auth(t).refresh(Self.cred())
        #expect(c.access == Secret("NEW-ACCESS"))
        #expect(c.refresh == Secret("OLD-REFRESH-SENTINEL"))
        #expect(c.remoteAccountID == "acct-synthetic")
        #expect(c.accountEmail == "grok@example.com")
    }

    @Test func refreshInvalidGrantIsNeedsLogin() async throws {
        for r in [Self.oauthError("invalid_grant"), (401, #"{"error":"invalid_client"}"#, [:])] {
            let t = ScriptedTransport([r])
            await #expect(throws: ProviderError.invalidGrant) { try await auth(t).refresh(Self.cred()) }
            #expect(t.requests.count == 1)
        }
    }

    @Test func refreshWithoutTokenNoRequest() async throws {
        for c in [Self.cred(refresh: nil), Self.cred(refresh: "")] {
            let t = ScriptedTransport([])
            await #expect(throws: ProviderError.invalidGrant) { try await auth(t).refresh(c) }
            #expect(t.requests.isEmpty)
        }
    }
}
