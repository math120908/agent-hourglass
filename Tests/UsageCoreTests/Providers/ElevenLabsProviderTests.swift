import Foundation
import Testing
@testable import UsageCore

struct ElevenLabsProviderTests {
    let account = AccountID(kind: .elevenlabs, remoteID: "u1")
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func credential(refresh: String? = "old-refresh") -> Credential {
        Credential(
            kind: .elevenlabs,
            access: Secret("old-id"),
            refresh: refresh.map(Secret.init),
            expiresAt: now,
            refreshExpiresAt: nil,
            scopes: [],
            remoteAccountID: "u1",
            accountEmail: "a@example.com"
        )
    }

    @Test func decodesCharacterMeter() throws {
        let s = try ElevenLabsProvider.decode(fixture("elevenlabs-creator"), accountID: account, now: now)
        #expect(s.plan == "Creator")
        #expect(s.meters.count == 1)
        let m = s.meters[0]
        #expect(m.used == 200)
        #expect(m.limit == 130539)
        #expect(m.percentUsed == 0.2)
        #expect(m.unit == "characters")
        #expect(m.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func missingCountsIsSchemaError() {
        #expect(throws: ProviderError.self) {
            try ElevenLabsProvider.decode(Data(#"{"tier":"free"}"#.utf8), accountID: account, now: now)
        }
    }

    @Test func planNameCapitalises() {
        #expect(ElevenLabsProvider.planName("creator") == "Creator")
        #expect(ElevenLabsProvider.planName("growing_business") == "Growing Business")
        #expect(ElevenLabsProvider.planName(nil) == nil)
    }

    @Test func subscriptionHostAllowed() { #expect(HTTPClient.authHosts.contains("api.us.elevenlabs.io")) }

    @Test func refreshRotatesTokens() async throws {
        let t = ScriptedTransport([(200, #"{"id_token":"new-id","refresh_token":"new-refresh","expires_in":"3600","user_id":"u1"}"#, [:])])
        let p = ElevenLabsProvider(now: { [now] in now })
        let c = try #require(try await p.refresh(credential: credential(), http: HTTPClient(transport: t)))
        #expect(c.access == Secret("new-id"))
        #expect(c.refresh == Secret("new-refresh"))
        #expect(c.expiresAt == now.addingTimeInterval(3600))
        #expect(c.accountEmail == "a@example.com")
        let req = t.requests[0]
        #expect(req.httpMethod == "POST")
        #expect(req.url?.host() == "securetoken.googleapis.com")
        #expect(req.value(forHTTPHeaderField: "Referer") == "https://elevenlabs.io/")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(t.bodyForm(0) == ["grant_type": "refresh_token", "refresh_token": "old-refresh"])
    }

    @Test func refresh400IsInvalidGrant() async {
        let t = ScriptedTransport([(400, #"{"error":{"message":"INVALID_REFRESH_TOKEN"}}"#, [:])])
        await #expect(throws: ProviderError.invalidGrant) {
            _ = try await ElevenLabsProvider().refresh(credential: credential(), http: HTTPClient(transport: t))
        }
    }

    @Test func refreshWithoutTokenIsInvalidGrant() async {
        await #expect(throws: ProviderError.invalidGrant) {
            _ = try await ElevenLabsProvider().refresh(credential: credential(refresh: nil), http: HTTPClient(transport: ScriptedTransport([])))
        }
    }

    @Test func fetchSendsBearer() async throws {
        let body = String(data: try fixture("elevenlabs-creator"), encoding: .utf8)!
        let t = ScriptedTransport([(200, body, [:])])
        let s = try await ElevenLabsProvider().fetch(credential: credential(), http: HTTPClient(transport: t))
        #expect(s.meters.first?.used == 200)
        #expect(t.requests[0].url == ElevenLabsProvider.subscriptionURL)
        #expect(t.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer old-id")
    }
}
