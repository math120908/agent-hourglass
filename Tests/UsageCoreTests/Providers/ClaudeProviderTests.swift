import Foundation
import Testing
@testable import UsageCore

final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    let status: Int
    let body: Data

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

struct ClaudeProviderTests {
    let account = AccountID(kind: .claude, remoteID: "ACCOUNT_ID")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cred = Credential(kind: .claude, access: Secret("tok-AAAA"), refresh: Secret("ref-BBBB"), expiresAt: nil, refreshExpiresAt: nil, scopes: ["user:profile"])

    @Test func newFormat() throws {
        let s = try ClaudeProvider.decodeUsage(fixture("claude-new"), accountID: account, now: now)
        #expect(s.meters.map(\.kind) == [.session5h, .weeklyAll, .weeklyModel])
        #expect(s.meters[2].label == "Fable")
        #expect(s.meters[1].percentUsed == 39)
        #expect(s.meters[0].windowLength == .seconds(5 * 3600))
        #expect(s.spend == Money(
            usedMinor: 85,
            limitMinor: 2000,
            currency: "EUR",
            exponent: 2,
            isEnabled: false,
            disabledReason: "out_of_credits"
        ))
    }

    @Test func legacyOnly() throws {
        let s = try ClaudeProvider.decodeUsage(fixture("claude-legacy-only"), accountID: account, now: now)
        #expect(s.meters.map(\.kind) == [.session5h, .weeklyAll])
        #expect(s.meters[0].percentUsed == 12.5)
    }

    /// Verified Ultra: no session limit, `five_hour` null, only weekly limits (live shape, 2026-10-31).
    @Test func weeklyOnlyUltra() throws {
        let s = try ClaudeProvider.decodeUsage(fixture("claude-weekly-only"), accountID: account, now: now)
        #expect(s.meters.map(\.kind) == [.weeklyAll, .weeklyModel])
        #expect(s.meters[0].percentUsed == 6)
        #expect(s.meters[1].label == "Fable")
    }

    /// Every fixture shape decodes to a snapshot whose card has a headline (or none only when all-null throws).
    @Test(arguments: ["claude-new", "claude-idle", "claude-legacy-only", "claude-weekly-only", "claude-spend-disabled", "claude-unknown-keys"])
    func everyPlanShapeHasHeadline(name: String) throws {
        let s = try ClaudeProvider.decodeUsage(fixture(name), accountID: account, now: now)
        #expect(CardModel.headlineMeter(s.meters, kind: .claude) != nil)
    }

    @Test func idleSessionNullReset() throws {
        let s = try ClaudeProvider.decodeUsage(fixture("claude-idle"), accountID: account, now: now)
        #expect(s.meters[0].resetsAt == nil)
        #expect(s.spend == nil)
    }

    @Test func spendDisabledStillParsed() throws {
        let s = try ClaudeProvider.decodeUsage(fixture("claude-spend-disabled"), accountID: account, now: now)
        #expect(s.spend?.usedMinor == 85)
        #expect(s.spend?.limitMinor == 2000)
        #expect(s.spend?.isEnabled == false)
        #expect(s.spend?.disabledReason == "out_of_credits")
        let rt = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(s))
        #expect(rt.spend == s.spend)
    }

    @Test func unknownKeysRecorded() throws {
        let s = try ClaudeProvider.decodeUsage(fixture("claude-unknown-keys"), accountID: account, now: now)
        #expect(s.rawUnknownKeys.contains("iguana_necktie"))
        #expect(s.rawUnknownKeys.contains("amber_cistern"))
        #expect(s.meters.map(\.kind) == [.session5h])
    }

    @Test func allNullIsSchemaError() throws {
        #expect(throws: ProviderError.self) {
            _ = try ClaudeProvider.decodeUsage(fixture("claude-all-null"), accountID: account, now: now)
        }
    }

    @Test func tokenResponse() throws {
        let (c, id, email) = try ClaudeProvider.decodeTokenResponse(fixture("claude-token-response"), now: now)
        #expect(c.expiresAt == now.addingTimeInterval(28800))
        #expect(c.refreshExpiresAt == now.addingTimeInterval(2_592_000))
        #expect(c.scopes == ["user:profile"])
        #expect(c.refresh != nil)
        #expect(id == "ACCOUNT_ID")
        #expect(email == "user@example.com")
    }

    @Test func tokenResponseMissingOptionalFields() throws {
        let body = Data(#"{"access_token":"x","expires_in":60}"#.utf8)
        #expect(throws: ProviderError.self) { _ = try ClaudeProvider.decodeTokenResponse(body, now: now) }
        let noRefreshExp = Data(#"{"access_token":"x","expires_in":60,"account":{"uuid":"A1"}}"#.utf8)
        let (c, id, email) = try ClaudeProvider.decodeTokenResponse(noRefreshExp, now: now)
        #expect(c.refresh == nil && c.refreshExpiresAt == nil && email == nil && id == "A1")
    }

    @Test func fetchSendsBetaHeader() async throws {
        let t = RecordingTransport(body: try fixture("claude-new"))
        let s = try await ClaudeProvider().fetch(credential: cred, http: HTTPClient(transport: t))
        let r = try #require(t.requests.first)
        #expect(r.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok-AAAA")
        #expect(s.meters.count == 3)
    }

    @Test func refreshPostsJSON() async throws {
        let t = RecordingTransport(body: try fixture("claude-token-response"))
        let c = try await ClaudeProvider().refresh(credential: cred, http: HTTPClient(transport: t))
        let r = try #require(t.requests.first)
        #expect(r.httpMethod == "POST")
        #expect(r.url?.absoluteString == "https://platform.claude.com/v1/oauth/token")
        let json = try JSONSerialization.jsonObject(with: try #require(r.httpBody)) as? [String: String]
        #expect(json?["grant_type"] == "refresh_token")
        #expect(json?["refresh_token"] == "ref-BBBB")
        #expect(json?["client_id"] == ClaudeOAuth.clientID)
        #expect(c?.access == Secret("x"))
    }

    @Test func refreshInvalidGrant() async throws {
        let t = RecordingTransport(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
        await #expect(throws: ProviderError.invalidGrant) {
            _ = try await ClaudeProvider().refresh(credential: cred, http: HTTPClient(transport: t))
        }
    }

    @Test func fetch401Unauthorized() async throws {
        let t = RecordingTransport(status: 401, body: Data())
        await #expect(throws: ProviderError.unauthorized) {
            _ = try await ClaudeProvider().fetch(credential: cred, http: HTTPClient(transport: t))
        }
    }
}
