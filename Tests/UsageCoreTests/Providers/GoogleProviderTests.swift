// Fixtures synthesized from R9 §2 (loadCodeAssist / retrieveUserQuotaSummary / fetchAvailableModels / retrieveUserQuota field lists).
import Foundation
import Testing
@testable import UsageCore

/// Hands out a fixed client and counts `invalidate()` calls.
actor StubGoogleClientSource: GoogleOAuthClientSource {
    private(set) var invalidations = 0
    func client() async throws -> GoogleOAuthClient { GoogleOAuthClient(secret: Secret("test-secret")) }
    func invalidate() async { invalidations += 1 }
}

/// Signed in as Google, but the OAuth client secret cannot be had.
struct ClientUnavailableProvider: UsageProvider {
    let kind: ProviderKind = .google
    let minimumInterval: Duration = .seconds(300)
    func fetch(credential: Credential, http: HTTPClient) async throws -> UsageSnapshot { throw GoogleOAuthError.clientUnavailable }
    func refresh(credential: Credential, http: HTTPClient) async throws -> Credential? { nil }
}

struct GoogleProviderTests {
    typealias Response = (status: Int, body: String, headers: [String: String])

    let provider = GoogleProvider(client: StubGoogleClientSource())
    let cred = Credential(kind: .google, access: Secret("ACCESS-SENTINEL"), refresh: Secret("REFRESH-SENTINEL"), expiresAt: nil, refreshExpiresAt: nil, scopes: [], remoteAccountID: "sub-1", accountEmail: "pat@example.com")

    static func ok(_ name: String) throws -> Response { (200, String(decoding: try fixture(name), as: UTF8.self), [:]) }
    static let forbidden: Response = (403, #"{"error":{"code":403}}"#, [:])
    static let notFound: Response = (404, "", [:])

    func fetch(_ t: ScriptedTransport, credential: Credential? = nil) async throws -> UsageSnapshot {
        try await provider.fetch(credential: credential ?? cred, http: HTTPClient(transport: t))
    }

    @Test func pinnedConstants() {
        #expect(provider.kind == .google)
        #expect(provider.minimumInterval == .seconds(300))
        #expect(GoogleProvider.hubUserAgent == "antigravity/hub/2.9.1 darwin/arm64")
        #expect(GoogleProvider.metadata == ["ideType": "ANTIGRAVITY", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"])
        #expect(GoogleProvider.prodBase.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal")
        #expect(GoogleProvider.dailyBase.absoluteString == "https://daily-cloudcode-pa.googleapis.com/v1internal")
        #expect(HTTPClient.authHosts.isSuperset(of: ["cloudcode-pa.googleapis.com", "daily-cloudcode-pa.googleapis.com"]))
    }

    @Test func happyPathUsesSummary() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), try Self.ok("google-summary")])
        let s = try await fetch(t)
        #expect(t.requests.count == 2)
        guard t.requests.count == 2 else { return }
        #expect(t.requests[0].url?.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
        #expect(t.requests[1].url?.absoluteString.hasSuffix(":retrieveUserQuotaSummary") == true)
        #expect(t.requests[1].url?.host == "daily-cloudcode-pa.googleapis.com")
        for r in t.requests {
            #expect(r.httpMethod == "POST")
            #expect(r.value(forHTTPHeaderField: "User-Agent") == GoogleProvider.hubUserAgent)
            #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(r.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer ACCESS-SENTINEL")
        }
        #expect((t.bodyJSON(0)?["metadata"] as? [String: Any])?["ideType"] as? String == "ANTIGRAVITY")
        #expect(t.bodyJSON(1)?["project"] as? String == "proj-synthetic")
        #expect(s.meters.count == 4)
        #expect(s.plan == "Google AI Pro")
        #expect(s.accountID == AccountID(kind: .google, remoteID: "sub-1"))
        #expect(s.rawUnknownKeys == ["futureField"])
    }

    @Test func tosIneligibleIsNeedsLogin() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-tos")])
        await #expect(throws: ProviderError.invalidGrant) { try await fetch(t) }
        #expect(t.requests.count == 1)
    }

    @Test func unsupportedClientIsNeedsLogin() async throws {
        let t = ScriptedTransport([(200, #"{"ineligibleTiers":[{"reasonCode":"UNSUPPORTED_CLIENT"}]}"#, [:])])
        await #expect(throws: ProviderError.invalidGrant) { try await fetch(t) }
        #expect(t.requests.count == 1)
    }

    @Test func noProjectNoReasonIsUnavailable() async throws {
        let t = ScriptedTransport([(200, #"{"currentTier":{"id":"free-tier"},"ineligibleTiers":[{"reasonCode":"OTHER"}]}"#, [:])])
        await #expect(throws: QuotaError.unavailable) { try await fetch(t) }
        #expect(t.requests.count == 1)
    }

    @Test func summary404FallsBackToModels() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.notFound, try Self.ok("google-models")])
        let s = try await fetch(t)
        #expect(t.requests.count == 3)
        guard t.requests.count == 3 else { return }
        #expect(t.requests[2].url?.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")
        #expect(t.bodyJSON(2)?["project"] as? String == "proj-synthetic")
        #expect(s.meters.map(\.pool) == ["claude-sonnet", "gemini-3-pro"])
        #expect(s.plan == "Google AI Pro")
    }

    @Test func summarySchemaFallsBackToModels() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), (200, #"{"groups":[]}"#, [:]), try Self.ok("google-models")])
        let s = try await fetch(t)
        #expect(t.requests.count == 3)
        #expect(s.meters.count == 2)
    }

    @Test func allFullModelsUnconfirmedIsUnavailable() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.notFound, try Self.ok("google-models-all-full"), Self.forbidden])
        await #expect(throws: QuotaError.unavailable) { try await fetch(t) }
        #expect(t.requests.count == 4)
        guard t.requests.count == 4 else { return }
        #expect(t.requests[3].url?.absoluteString == "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
    }

    @Test func allFullModelsEmptyQuotaIsUnavailable() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.notFound, try Self.ok("google-models-all-full"), (200, #"{"buckets":[]}"#, [:])])
        await #expect(throws: QuotaError.unavailable) { try await fetch(t) }
        #expect(t.requests.count == 4)
    }

    @Test func allFullModelsConfirmedIsReal() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.notFound, try Self.ok("google-models-all-full"), try Self.ok("google-quota")])
        let s = try await fetch(t)
        #expect(t.requests.count == 4)
        #expect(s.meters.map(\.pool) == ["claude-sonnet", "gemini-3-pro"])
        #expect(s.meters.allSatisfy { $0.percentUsed == 0 })
    }

    @Test func models403QuotaOkUsesQuota() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.forbidden, Self.forbidden, try Self.ok("google-quota")])
        let s = try await fetch(t)
        #expect(t.requests.count == 4)
        let m = try #require(s.meters.first)
        #expect(s.meters.count == 1)
        #expect(m.kind == .window && m.label == "gemini-3-pro" && m.pool == "gemini-3-pro" && m.windowLength == nil)
        #expect(m.percentUsed == 0)
    }

    @Test func all403IsUnavailable() async throws {
        let t = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.forbidden, Self.forbidden, Self.forbidden])
        await #expect(throws: QuotaError.unavailable) { try await fetch(t) }
        #expect(t.requests.count == 4)
    }

    @Test func unauthorizedPropagates() async throws {
        let first = ScriptedTransport([(401, "", [:])])
        await #expect(throws: ProviderError.unauthorized) { try await fetch(first) }
        #expect(first.requests.count == 1)
        let summary = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), (401, "", [:])])
        await #expect(throws: ProviderError.unauthorized) { try await fetch(summary) }
        let quota = ScriptedTransport([try Self.ok("google-loadcodeassist-pro"), Self.forbidden, Self.forbidden, (401, "", [:])])
        await #expect(throws: ProviderError.unauthorized) { try await fetch(quota) }
    }

    @Test func missingRemoteIDIsInvalidGrant() async throws {
        var c = cred
        c.remoteAccountID = nil
        let t = ScriptedTransport([])
        await #expect(throws: ProviderError.invalidGrant) { try await fetch(t, credential: c) }
        #expect(t.requests.count == 0)
    }

    @Test func refreshKeepsRefreshToken() async throws {
        let t = ScriptedTransport([(200, #"{"access_token":"NEW-ACCESS","expires_in":3599}"#, [:])])
        let fresh = try #require(try await provider.refresh(credential: cred, http: HTTPClient(transport: t)))
        #expect(fresh.access.reveal() == "NEW-ACCESS")
        #expect(fresh.refresh?.reveal() == "REFRESH-SENTINEL")
        #expect(t.bodyForm(0)["client_secret"] == "test-secret")
    }

    @Test func refreshClientRejectedInvalidates() async throws {
        let source = StubGoogleClientSource()
        let t = ScriptedTransport([(401, #"{"error":"invalid_client"}"#, [:])])
        await #expect(throws: GoogleOAuthError.clientRejected) {
            try await GoogleProvider(client: source).refresh(credential: cred, http: HTTPClient(transport: t))
        }
        #expect(await source.invalidations == 1)
    }

    @Test func shapeLogsCarryNoIdentity() throws {
        let token = Data(#"{"access_token":"ACCESS-SENTINEL","refresh_token":"REFRESH-SENTINEL","id_token":"ID-SENTINEL","email":"pat@example.com","scope":"s"}"#.utf8)
        let inputs = [
            try fixture("google-loadcodeassist-pro"),
            try fixture("google-loadcodeassist-object-project"),
            Data(#"{"cloudaicompanionProject":{"id":"proj-synthetic","name":"proj-synthetic"},"user":{"email":"pat@example.com"}}"#.utf8),
            token,
        ]
        for data in inputs {
            let out = ResponseShape.describe(data, keep: GoogleProvider.shapeKeep)
            for secret in ["proj-synthetic", "pat@example.com", "ACCESS-SENTINEL", "REFRESH-SENTINEL", "ID-SENTINEL"] {
                #expect(!out.contains(secret), "\(secret) leaked: \(out)")
            }
        }
    }

    @Test func clientUnavailableReportsNeedsLogin() async throws {
        let id = AccountID(kind: .google, remoteID: "sub-1")
        let store = InMemoryCredentialStore()
        try store.write(cred, for: id, label: "t")
        let client = AccountClient(id: id, provider: ClientUnavailableProvider(), http: HTTPClient(), store: store, clock: ContinuousClock(), now: { Date() })
        #expect(await client.fetch() == .failure(.needsLogin))
    }
}
