import Foundation
import Testing
@testable import UsageCore

// Fixtures synthesized from R10 §2a (CLI-proxy billing) and ClaudeBar `docs/providers/grok/design.md`.
struct GrokBillingDecodingTests {
    let weekEnd = CodexDeviceAuth.date("2026-11-02T00:00:00Z")

    @Test func weeklyWithProducts() throws {
        let r = try GrokBillingDecoding.decode(fixture("grok-billing-weekly"))
        #expect(r.meters.map(\.label) == ["Weekly", "Build, weekly", "Chat, weekly"])
        #expect(r.meters.map(\.percentUsed) == [96, 84, 12])
        #expect(r.meters.map(\.pool) == [nil, "build", "chat"])
        #expect(r.meters.allSatisfy { $0.kind == .window && $0.windowSeconds == 604_800 && $0.resetsAt == weekEnd })
        #expect(r.spend == Money(usedMinor: 420, limitMinor: nil, currency: "USD", exponent: 2))
        #expect(r.unknownKeys.contains("futureKey"))
    }

    @Test func unwrappedSameAsWrapped() throws {
        let wrapped = try GrokBillingDecoding.decode(fixture("grok-billing-weekly"))
        let bare = try GrokBillingDecoding.decode(fixture("grok-billing-unwrapped"))
        #expect(bare.meters == wrapped.meters)
        #expect(bare.spend == wrapped.spend)
        #expect(bare.unknownKeys == wrapped.unknownKeys)
    }

    @Test func periodStartPercentIsNil() throws {
        let r = try GrokBillingDecoding.decode(fixture("grok-billing-period-start"))
        #expect(r.meters.count == 1)
        #expect(r.meters[0].label == "Weekly")
        #expect(r.meters[0].percentUsed == nil)
        #expect(r.meters[0].resetsAt == CodexDeviceAuth.date("2026-11-09T00:00:00Z"))
        #expect(r.spend == nil)
    }

    @Test func monthlyWindowFromDates() throws {
        let r = try GrokBillingDecoding.decode(fixture("grok-billing-monthly"))
        #expect(r.meters.count == 1)
        #expect(r.meters[0].windowSeconds == 2_592_000)
        #expect(r.meters[0].label == "30-day")
        #expect(r.meters[0].percentUsed == 40)
    }

    @Test func onDemandSpend() throws {
        let r = try GrokBillingDecoding.decode(fixture("grok-billing-ondemand"))
        #expect(r.spend == Money(usedMinor: 350, limitMinor: 2000, currency: "USD", exponent: 2))
    }

    @Test func emptyIsSchema() {
        #expect(throws: ProviderError.schema(keys: ["config"])) {
            try GrokBillingDecoding.decode(Data(#"{"config":{}}"#.utf8))
        }
        #expect(throws: ProviderError.schema(keys: [])) {
            try GrokBillingDecoding.decode(Data("[]".utf8))
        }
    }

    @Test func nonFinitePercentIsUnknown() throws {
        let r = try GrokBillingDecoding.decode(Data(#"{"creditUsagePercent":"NaN","productUsage":[{"product":"Chat","usagePercent":"Infinity"}]}"#.utf8))
        #expect(r.meters.map(\.percentUsed) == [nil, nil])
        #expect(r.meters[0].label == "Usage")
        #expect(r.meters[1].label == "Chat, usage")
    }

    @Test func malformedProductsSkipped() throws {
        let body = #"{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_DAILY"},"billingPeriodEnd":1800000000,"productUsage":[7,{"usagePercent":5},{"product":"Voice","usagePercent":3}]}"#
        let r = try GrokBillingDecoding.decode(Data(body.utf8))
        #expect(r.meters.map(\.label) == ["1-day", "Voice, 1-day"])
        #expect(r.meters.map(\.windowSeconds) == [86400, 86400])
        #expect(r.meters[0].resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func planFromSettings() throws {
        #expect(GrokBillingDecoding.plan(try fixture("grok-settings")) == "SuperGrok")
        #expect(GrokBillingDecoding.plan(Data(#"{"subscription_tier_display":""}"#.utf8)) == nil)
        #expect(GrokBillingDecoding.plan(Data("nope".utf8)) == nil)
    }
}
