import Foundation
import Testing
@testable import UsageCore

// Fixtures synthesized from R10 §2a (CLI-proxy billing + settings) and ClaudeBar `docs/providers/grok/design.md`.
struct GrokProviderTests {
    let provider = GrokProvider()
    let id = AccountID(kind: .grok, remoteID: "acct-synthetic")

    static func body(_ name: String) throws -> String { String(decoding: try fixture(name), as: UTF8.self) }

    func cred(account: String? = "acct-synthetic") -> Credential {
        Credential(kind: .grok, access: Secret("tok-grok"), refresh: Secret("ref-grok"), expiresAt: nil, refreshExpiresAt: nil, scopes: [], remoteAccountID: account)
    }

    func fetch(_ responses: [(status: Int, body: String, headers: [String: String])]) async throws -> (UsageSnapshot, ScriptedTransport) {
        let t = ScriptedTransport(responses)
        let s = try await provider.fetch(credential: cred(), http: HTTPClient(transport: t))
        return (s, t)
    }

    @Test func fetchSendsBothClientHeaders() async throws {
        let (_, t) = try await fetch([(200, try Self.body("grok-billing-weekly"), [:]), (200, try Self.body("grok-settings"), [:])])
        #expect(provider.kind == .grok && provider.minimumInterval == .seconds(300))
        #expect(t.requests.map(\.url) == [GrokProvider.billingURL, GrokProvider.settingsURL])
        for r in t.requests {
            #expect(r.value(forHTTPHeaderField: "x-xai-token-auth") == "xai-grok-cli")
            #expect(r.value(forHTTPHeaderField: "x-grok-client-mode") == "build")
            #expect(r.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok-grok")
        }
    }

    @Test func fetchBuildsSnapshotWithPlan() async throws {
        let (s, _) = try await fetch([(200, try Self.body("grok-billing-weekly"), [:]), (200, try Self.body("grok-settings"), [:])])
        #expect(s.accountID == id)
        #expect(s.plan == "SuperGrok")
        #expect(s.meters.map(\.label) == ["Weekly", "Build, weekly", "Chat, weekly"])
        #expect(s.meters.map(\.percentUsed) == [96, 84, 12])
        #expect(s.spend == nil)
        #expect(s.rawUnknownKeys.contains("futureKey"))
    }

    @Test func billing403IsQuotaUnavailable() async throws {
        let t = ScriptedTransport([(403, #"{"error":"insufficient scope"}"#, [:])])
        await #expect(throws: QuotaError.unavailable) {
            try await provider.fetch(credential: cred(), http: HTTPClient(transport: t))
        }
        #expect(t.requests.count == 1)
    }

    @Test func settingsFailureKeepsSnapshot() async throws {
        let (s, t) = try await fetch([(200, try Self.body("grok-billing-weekly"), [:]), (500, "", [:])])
        #expect(t.requests.count == 2)
        #expect(s.plan == nil)
        #expect(s.meters.count == 3)
    }

    @Test func settingsUnauthorizedPropagates() async throws {
        let t = ScriptedTransport([(200, try Self.body("grok-billing-weekly"), [:]), (401, "", [:])])
        await #expect(throws: ProviderError.unauthorized) {
            try await provider.fetch(credential: cred(), http: HTTPClient(transport: t))
        }
    }

    @Test func billingUnauthorizedPropagates() async {
        let t = ScriptedTransport([(401, "", [:])])
        await #expect(throws: ProviderError.unauthorized) {
            try await provider.fetch(credential: cred(), http: HTTPClient(transport: t))
        }
        #expect(t.requests.count == 1)
    }

    @Test func missingRemoteIDIsInvalidGrant() async {
        let t = ScriptedTransport([])
        await #expect(throws: ProviderError.invalidGrant) {
            try await provider.fetch(credential: cred(account: nil), http: HTTPClient(transport: t))
        }
        await #expect(throws: ProviderError.invalidGrant) {
            try await provider.fetch(credential: cred(account: ""), http: HTTPClient(transport: t))
        }
        #expect(t.requests.count == 0)
    }

    @Test func responseShapeHasNoToken() throws {
        #expect(GrokProvider.logKeep == ["type", "product", "subscription_tier_display", "start", "end"])
        let billing = ResponseShape.describe(try fixture("grok-billing-weekly"), keep: GrokProvider.logKeep)
        #expect(billing.contains("USAGE_PERIOD_TYPE_WEEKLY") && billing.contains("GrokBuild"))
        let settings = #"{"subscription_tier_display":"SuperGrok","access_token":"tok-grok","refresh_token":"rt-grok","id_token":"idt-grok","user_id":"uid-grok-PII","email":"pii@example.com","name":"user-PII"}"#
        let shape = ResponseShape.describe(Data(settings.utf8), keep: GrokProvider.logKeep)
        #expect(shape.contains("SuperGrok"))
        for leak in ["tok-grok", "rt-grok", "idt-grok", "uid-grok-PII", "Bearer", "pii@example.com", "user-PII"] {
            #expect(!billing.contains(leak) && !shape.contains(leak))
        }
    }
}
