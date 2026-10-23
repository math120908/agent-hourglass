import Foundation
import Testing
@testable import UsageCore

final class CodexTestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.withLock { v } } set { lock.withLock { v = newValue } } }
}

struct CodexDeviceAuthTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = CodexTestBox(t0)
    let sleeps = CodexTestBox<[Duration]>([])

    static func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func jwt(_ payload: String) -> String { "\(b64url("{\"alg\":\"none\"}")).\(b64url(payload)).sig" }
    static let idToken = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-synthetic"},"email":"x@y"}"#)
    static let accessToken = jwt(#"{"exp":1800003600}"#)
    static let start = (200, #"{"device_auth_id":"DAID-SENTINEL","user_code":"ABCD-1234","interval":"5"}"#, [String: String]())
    static let code = (200, #"{"authorization_code":"AUTHCODE-SENTINEL","code_challenge":"c","code_verifier":"VERIFIER-SENTINEL"}"#, [String: String]())
    static func tokens(expiresIn: Bool = false, id: String = idToken) -> (Int, String, [String: String]) {
        let e = expiresIn ? #","expires_in":864000"# : ""
        return (200, "{\"id_token\":\"\(id)\",\"access_token\":\"\(accessToken)\",\"refresh_token\":\"REFRESH-SENTINEL\"\(e)}", [:])
    }
    static let pending = (403, "", [String: String]())

    func auth(_ t: ScriptedTransport, advance: TimeInterval = 0) -> CodexDeviceAuth {
        let clock = clock, sleeps = sleeps
        return CodexDeviceAuth(
            http: HTTPClient(transport: t),
            sleep: { d in sleeps.value.append(d); clock.value = clock.value.addingTimeInterval(advance) },
            now: { clock.value }
        )
    }

    func prompt(interval: Duration = .seconds(5), expiresAt: Date? = nil) -> DeviceCodePrompt {
        DeviceCodePrompt(
            userCode: "ABCD-1234",
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            interval: interval,
            expiresAt: expiresAt ?? Self.t0.addingTimeInterval(900),
            deviceCode: Secret("DAID-SENTINEL")
        )
    }

    @Test func startSendsClientIDAndBuildsPrompt() async throws {
        let t = ScriptedTransport([Self.start])
        let p = try await auth(t).start()
        try #require(t.requests.count == 1)
        #expect(t.requests[0].url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/usercode")
        #expect(t.requests[0].httpMethod == "POST")
        #expect(t.bodyJSON(0)?["client_id"] as? String == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(p.userCode == "ABCD-1234")
        #expect(p.interval == .seconds(5))
        #expect(p.verificationURL.absoluteString == "https://auth.openai.com/codex/device")
        #expect(p.expiresAt == Self.t0.addingTimeInterval(900))
        #expect(p.deviceCode.reveal() == "DAID-SENTINEL")
    }

    @Test func startAcceptsUsercodeAliasAndIntInterval() async throws {
        let t = ScriptedTransport([(200, #"{"device_auth_id":"D","usercode":"WXYZ-9","interval":8,"verification_uri":"https://evil.example/x"}"#, [:])])
        let p = try await auth(t).start()
        #expect(p.userCode == "WXYZ-9")
        #expect(p.interval == .seconds(8))
        #expect(p.verificationURL.host() == "auth.openai.com")
    }

    @Test func zeroIntervalUsesFloor() async throws {
        let t = ScriptedTransport([(200, #"{"device_auth_id":"D","user_code":"U","interval":0}"#, [:])])
        #expect(try await auth(t).start().interval == .seconds(5))
        let t2 = ScriptedTransport([Self.pending, Self.code, Self.tokens()])
        _ = try await auth(t2).poll(prompt(interval: .zero))
        #expect(sleeps.value == [.seconds(5)])
    }

    @Test func missingIntervalUsesFloor() async throws {
        for body in [#"{"device_auth_id":"D","user_code":"U"}"#, #"{"device_auth_id":"D","user_code":"U","interval":"abc"}"#, #"{"device_auth_id":"D","user_code":"U","interval":"2"}"#] {
            let t = ScriptedTransport([(200, body, [:])])
            #expect(try await auth(t).start().interval == .seconds(5))
        }
    }

    @Test func slowDownAddsFiveSeconds() async throws {
        let t = ScriptedTransport([(429, "", [:]), Self.pending, Self.code, Self.tokens()])
        _ = try await auth(t).poll(prompt())
        #expect(sleeps.value == [.seconds(10), .seconds(10)])
    }

    @Test func pollPendingThenSuccessExchanges() async throws {
        let t = ScriptedTransport([Self.pending, (404, "", [:]), Self.code, Self.tokens()])
        _ = try await auth(t).poll(prompt())
        #expect(sleeps.value == [.seconds(5), .seconds(5)])
        try #require(t.requests.count == 4)
        #expect(t.requests[0].url?.absoluteString == "https://auth.openai.com/api/accounts/deviceauth/token")
        #expect(t.bodyJSON(0)?["device_auth_id"] as? String == "DAID-SENTINEL")
        #expect(t.bodyJSON(0)?["user_code"] as? String == "ABCD-1234")
        #expect(t.requests[3].url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(t.requests[3].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(t.bodyForm(3) == [
            "grant_type": "authorization_code",
            "code": "AUTHCODE-SENTINEL",
            "redirect_uri": "https://auth.openai.com/deviceauth/callback",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "code_verifier": "VERIFIER-SENTINEL",
        ])
    }

    @Test func credentialFromTokens() async throws {
        let t = ScriptedTransport([Self.code, Self.tokens()])
        let c = try await auth(t).poll(prompt())
        #expect(c.kind == .codex)
        #expect(c.access.reveal() == Self.accessToken)
        #expect(c.refresh?.reveal() == "REFRESH-SENTINEL")
        #expect(c.remoteAccountID == "acct-synthetic")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(c.scopes == [])
        let enc = String(data: try JSONEncoder().encode(c), encoding: .utf8) ?? ""
        #expect(!enc.contains(Self.idToken))
        let t2 = ScriptedTransport([Self.code, Self.tokens(expiresIn: true)])
        #expect(try await auth(t2).poll(prompt()).expiresAt == Self.t0.addingTimeInterval(864000))
    }

    @Test func pollExpires() async throws {
        let t = ScriptedTransport([Self.pending, Self.pending])
        await #expect(throws: DeviceFlowError.expired) { try await auth(t, advance: 600).poll(prompt()) }
        #expect(t.requests.count == 2)
    }

    @Test func expiryCappedAtFifteenMinutes() async throws {
        let t = ScriptedTransport([Self.pending, Self.pending])
        let far = prompt(expiresAt: Self.t0.addingTimeInterval(86400))
        await #expect(throws: DeviceFlowError.expired) { try await auth(t, advance: 600).poll(far) }
        #expect(t.requests.count == 2)
    }

    @Test func pollUnexpectedStatus() async throws {
        let t = ScriptedTransport([(500, "", [:])])
        await #expect(throws: DeviceFlowError.unexpected(status: 500)) { try await auth(t).poll(prompt()) }
    }

    @Test func missingAccountClaimIsSchemaError() async throws {
        let t = ScriptedTransport([Self.code, Self.tokens(id: Self.jwt(#"{"sub":"x"}"#))])
        await #expect(throws: ProviderError.schema(keys: ["chatgpt_account_id"])) { try await auth(t).poll(prompt()) }
    }

    @Test func redirectIsNotFollowed() async throws {
        let t = ScriptedTransport([(302, "", ["Location": "https://evil.example/"])])
        await #expect(throws: DeviceFlowError.unexpected(status: 302)) { try await auth(t).poll(prompt()) }
        #expect(t.requests.count == 1)
        #expect(HTTPClient.noRedirectHosts.contains("auth.openai.com"))
    }

    @Test func cancellationStopsPolling() async throws {
        let t = ScriptedTransport([Self.pending, Self.pending])
        let a = CodexDeviceAuth(http: HTTPClient(transport: t), sleep: { _ in try await Task.sleep(for: .seconds(60)) }, now: { Self.t0 })
        let task = Task { try await a.poll(prompt()) }
        while t.requests.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(t.requests.count == 1)
    }

    @Test func noSecretsInErrors() async throws {
        let secrets = ["DAID-SENTINEL", "AUTHCODE-SENTINEL", "VERIFIER-SENTINEL", "REFRESH-SENTINEL", Self.accessToken, Self.idToken, "acct-synthetic"]
        let scripts: [[(Int, String, [String: String])]] = [
            [(500, "DAID-SENTINEL", [:])],
            [Self.code, (400, "AUTHCODE-SENTINEL", [:])],
            [Self.code, Self.tokens(id: Self.jwt(#"{"sub":"x"}"#))],
            [(200, #"{"authorization_code":"AUTHCODE-SENTINEL"}"#, [:])],
        ]
        for s in scripts {
            do { _ = try await auth(ScriptedTransport(s)).poll(prompt()); Issue.record("expected throw") } catch {
                for secret in secrets { #expect(!"\(error)".contains(secret)); #expect(!String(reflecting: error).contains(secret)) }
            }
        }
        let c = try await auth(ScriptedTransport([Self.code, Self.tokens()])).poll(prompt())
        for secret in secrets { #expect(!"\(c)".contains(secret)) }
    }

    static func cred(refresh: String? = "OLD-REFRESH-SENTINEL", account: String? = "acct-old") -> Credential {
        Credential(kind: .codex, access: Secret("OLD-ACCESS"), refresh: refresh.map(Secret.init), expiresAt: t0, refreshExpiresAt: nil, scopes: [], remoteAccountID: account)
    }

    @Test func refreshSendsRotatingRequest() async throws {
        let t = ScriptedTransport([(200, #"{"access_token":"NEW-ACCESS","refresh_token":"NEW-REFRESH"}"#, [:])])
        _ = try await auth(t).refresh(Self.cred())
        #expect(t.requests.count == 1)
        let r = t.requests[0]
        #expect(r.url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(r.timeoutInterval < 10)
        let body = t.bodyJSON(0) as? [String: String]
        #expect(body == ["client_id": CodexDeviceAuth.clientID, "grant_type": "refresh_token", "refresh_token": "OLD-REFRESH-SENTINEL", "scope": "openid profile email"])
    }

    @Test func refreshKeepsAccountIDAndOldRefreshWhenAbsent() async throws {
        let t = ScriptedTransport([(200, #"{"access_token":"NEW-ACCESS","expires_in":864000}"#, [:])])
        let c = try await auth(t).refresh(Self.cred())
        #expect(c.access == Secret("NEW-ACCESS"))
        #expect(c.refresh == Secret("OLD-REFRESH-SENTINEL"))
        #expect(c.remoteAccountID == "acct-old")
        #expect(c.expiresAt == Self.t0.addingTimeInterval(864000))
        #expect(c.earliestRefreshAt == nil)
    }

    @Test func refreshAdoptsNewRefreshAndAccountID() async throws {
        let id = Self.jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-new"}}"#)
        let body = "{\"access_token\":\"NEW-ACCESS\",\"refresh_token\":\"NEW-REFRESH\",\"id_token\":\"\(id)\",\"earliest_refresh_at\":1800001000}"
        let c = try await auth(ScriptedTransport([(200, body, [:])])).refresh(Self.cred())
        #expect(c.refresh == Secret("NEW-REFRESH"))
        #expect(c.remoteAccountID == "acct-new")
        #expect(c.earliestRefreshAt == Date(timeIntervalSince1970: 1_800_001_000))
        #expect(c.expiresAt == nil)
    }

    @Test func reusedOrExpiredIsInvalidGrant() async throws {
        let cases: [(Int, String, [String: String])] = [
            (400, #"{"error":"refresh_token_reused"}"#, [:]),
            (401, "", [:]),
            (400, #"{"error":{"code":"refresh_token_expired"}}"#, [:]),
            (200, #"{"error":"refresh_token_invalidated"}"#, [:]),
        ]
        for r in cases {
            let t = ScriptedTransport([r])
            await #expect(throws: ProviderError.invalidGrant) { try await auth(t).refresh(Self.cred()) }
            #expect(t.requests.count == 1)
        }
    }

    @Test func rateLimitPropagates() async throws {
        let t = ScriptedTransport([(429, "", [:])])
        await #expect(throws: ProviderError.rateLimited(retryAfter: nil)) { try await auth(t).refresh(Self.cred()) }
    }

    @Test func missingRefreshTokenIsInvalidGrant() async throws {
        let t = ScriptedTransport([])
        await #expect(throws: ProviderError.invalidGrant) { try await auth(t).refresh(Self.cred(refresh: nil)) }
        #expect(t.requests.isEmpty)
    }

    @Test func exchangeSetsEarliestRefreshAtISO() async throws {
        let body = "{\"id_token\":\"\(Self.idToken)\",\"access_token\":\"\(Self.accessToken)\",\"refresh_token\":\"R\",\"earliest_refresh_at\":\"2027-01-15T08:00:00Z\"}"
        let c = try await auth(ScriptedTransport([Self.code, (200, body, [:])])).poll(prompt())
        #expect(c.earliestRefreshAt == ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z"))
    }

    @Test func shouldRefreshHonoursEarliestUnlessExpired() {
        var c = Self.cred()
        c.expiresAt = Self.t0.addingTimeInterval(3600)
        c.earliestRefreshAt = Self.t0.addingTimeInterval(600)
        #expect(!CodexDeviceAuth.shouldRefresh(c, now: Self.t0))
        #expect(CodexDeviceAuth.shouldRefresh(c, now: Self.t0.addingTimeInterval(600)))
        c.expiresAt = Self.t0.addingTimeInterval(-1)
        #expect(CodexDeviceAuth.shouldRefresh(c, now: Self.t0))
        c.expiresAt = Self.t0.addingTimeInterval(3600); c.earliestRefreshAt = nil
        #expect(CodexDeviceAuth.shouldRefresh(c, now: Self.t0))
    }

    @Test func refreshErrorsCarryNoSecrets() async throws {
        let t = ScriptedTransport([(500, "OLD-REFRESH-SENTINEL", [:])])
        do { _ = try await auth(t).refresh(Self.cred()); Issue.record("expected throw") } catch {
            #expect(!"\(error)".contains("OLD-REFRESH-SENTINEL"))
        }
    }
}
