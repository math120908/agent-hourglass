import Foundation
import Testing
@testable import UsageCore

struct CopilotProviderTests {
    let account = AccountID(kind: .copilot, remoteID: "1")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func decode(_ name: String) throws -> UsageSnapshot {
        try CopilotProvider.decode(fixture(name), accountID: account, now: now)
    }

    @Test func enterprisePremium() throws {
        let s = try decode("copilot-enterprise")
        #expect(s.plan == "Enterprise")
        #expect(s.meters.map(\.kind) == [.copilotPremium])
        let m = s.meters[0]
        #expect(m.used == 84053)
        #expect(m.limit == 250000)
        #expect(m.percentUsed == 33.7)
        #expect(m.unit == "credits")
        #expect(m.resetsAt == ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        #expect(s.spend == nil)
    }

    @Test func individualZeroPremiumNotIncluded() throws {
        let s = try decode("copilot-individual")
        #expect(s.plan == "Pro")
        #expect(s.meters.map(\.kind) == [.copilotPremium, .copilotChat, .copilotCompletions])
        #expect(s.meters[0].limit == 0)
        #expect(s.meters[0].percentUsed == nil)
        #expect(s.meters[0].isUnlimited == false)
        #expect(s.meters[1].limit == 200 && s.meters[1].percentUsed == 0)
        #expect(s.meters[0].resetsAt != nil)
    }

    @Test func unlimitedHidden() throws {
        let s = try decode("copilot-unlimited")
        #expect(s.meters.count == 1)
        #expect(s.meters[0].isUnlimited)
        #expect(!CardModel.isVisible(s.meters[0]))
    }

    @Test func noQuotaSnapshots() throws {
        #expect(throws: ProviderError.self) { try decode("copilot-no-quota") }
        #expect(throws: ProviderError.self) {
            try CopilotProvider.decode(Data("[]".utf8), accountID: account, now: now)
        }
    }

    @Test func overageLine() throws {
        var root = try #require(JSONSerialization.jsonObject(with: fixture("copilot-enterprise")) as? [String: Any])
        var q = try #require(root["quota_snapshots"] as? [String: Any])
        var p = try #require(q["premium_interactions"] as? [String: Any])
        p["overage_permitted"] = true
        p["overage_count"] = 1234
        q["premium_interactions"] = p
        root["quota_snapshots"] = q
        let s = try CopilotProvider.decode(JSONSerialization.data(withJSONObject: root), accountID: account, now: now)
        #expect(s.spend == Money(usedMinor: 1234, limitMinor: nil, currency: "USD", exponent: 2))
    }

    @Test func fetchUsesMockTransport() async throws {
        let t = RecordingTransport(body: try fixture("copilot-enterprise"))
        let cred = Credential(kind: .copilot, access: Secret("tok-AAAA"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
        let s = try await CopilotProvider().fetch(credential: cred, http: HTTPClient(transport: t))
        #expect(s.meters[0].used == 84053)
        #expect(t.requests.first?.url == CopilotProvider.userURL)
        #expect(t.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-AAAA")
        #expect(try await CopilotProvider().refresh(credential: cred, http: HTTPClient(transport: t)) == nil)
    }
}
