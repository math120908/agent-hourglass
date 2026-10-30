// Fixtures synthesized from R9 §2 (loadCodeAssist / retrieveUserQuotaSummary field lists) and CodexBar AntigravityQuotaSummaryParser.swift:129-160.
import Foundation
import Testing
@testable import UsageCore

struct GoogleQuotaDecodingTests {
    @Test func proTierParsed() throws {
        let info = try GoogleQuotaDecoding.codeAssist(fixture("google-loadcodeassist-pro"))
        #expect(info.tierID == "g1-pro-tier")
        #expect(info.planLabel == "Google AI Pro")
        #expect(info.project == "proj-synthetic")
        #expect(info.ineligibleReasons.isEmpty)
        #expect(info.unknownKeys == ["futureField"])
    }

    @Test func tosPlaceholderParsed() throws {
        let info = try GoogleQuotaDecoding.codeAssist(fixture("google-loadcodeassist-tos"))
        #expect(info.project == nil)
        #expect(info.tierID == nil)
        #expect(info.planLabel == nil)
        #expect(info.ineligibleReasons == ["GOOGLE_TOS_NOT_SUPPORTED_BY_CLIENT"])
    }

    @Test func objectProjectParsed() throws {
        let info = try GoogleQuotaDecoding.codeAssist(fixture("google-loadcodeassist-object-project"))
        #expect(info.project == "proj-synthetic")
        #expect(info.planLabel == "Antigravity Starter Quota")
    }

    @Test func codeAssistNonObjectIsSchema() {
        #expect(throws: ProviderError.self) { try GoogleQuotaDecoding.codeAssist(Data("[]".utf8)) }
    }

    @Test func summaryFourMeters() throws {
        let meters = try GoogleQuotaDecoding.summaryMeters(fixture("google-summary"))
        #expect(meters.map(\.label) == ["Gemini, 5-hour", "Gemini, weekly", "Claude + GPT, 5-hour", "Claude + GPT, weekly"])
        #expect(meters.map(\.pool) == ["gemini", "gemini", "claude-gpt", "claude-gpt"])
        let expected: [Double] = [38, 10, 75, 50]
        #expect(meters.count == expected.count)
        for (m, p) in zip(meters, expected) { #expect(abs((m.percentUsed ?? -1) - p) < 0.001) }
        #expect(meters.allSatisfy { $0.kind == .window })
        #expect(meters[0].windowSeconds == 18000)
        #expect(meters[1].windowSeconds == 604_800)
        #expect(meters[0].resetsAt == ISO8601DateFormatter().date(from: "2026-10-30T06:00:00Z"))
        #expect(meters[1].resetsAt != nil)  // fractional seconds
    }

    @Test func summaryFlatAndUnknownWindow() throws {
        let meters = try GoogleQuotaDecoding.summaryMeters(fixture("google-summary-flat"))
        #expect(meters.count == 2)
        #expect(abs((meters[0].percentUsed ?? -1) - 60) < 0.001)
        let custom = meters[1]
        #expect(custom.windowLength == nil)
        #expect(custom.label == "Gemini, Custom limit")
        #expect(custom.pool == "gemini.x-custom")
        #expect(abs((custom.percentUsed ?? -1) - 20) < 0.001)
        #expect(Set(meters.map(\.pool)).count == meters.count)
    }

    @Test func missingFractionIsNilAndOutOfRangeClamped() throws {
        let body = """
        {"groups":[{"displayName":"Gemini models","buckets":[
          {"bucketId":"gemini-5h","window":"5h"},
          {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":-0.5}]}]}
        """
        let meters = try GoogleQuotaDecoding.summaryMeters(Data(body.utf8))
        #expect(meters[0].percentUsed == nil)
        #expect(meters[1].percentUsed == 100)
    }

    @Test func nonFiniteFractionIsUnknown() throws {
        let body = """
        {"groups":[{"displayName":"Gemini models","buckets":[
          {"bucketId":"gemini-5h","window":"5h","remainingFraction":"NaN"},
          {"bucketId":"gemini-weekly","window":"weekly","remaining":{"remainingFraction":"Infinity"}},
          {"bucketId":"gemini-daily","window":"daily","remainingFraction":"-Infinity"}]}]}
        """
        let meters = try GoogleQuotaDecoding.summaryMeters(Data(body.utf8))
        #expect(meters.count == 3)
        #expect(meters.allSatisfy { $0.percentUsed == nil })
    }

    @Test func summaryWithoutGroupsIsSchema() {
        #expect(throws: ProviderError.self) { try GoogleQuotaDecoding.summaryMeters(Data("{}".utf8)) }
    }

    @Test func summaryWithOnlyDisabledBucketsIsSchema() {
        let body = #"{"groups":[{"displayName":"Gemini models","buckets":[{"bucketId":"gemini-5h","disabled":true}]}]}"#
        #expect(throws: ProviderError.self) { try GoogleQuotaDecoding.summaryMeters(Data(body.utf8)) }
    }

    @Test func windowSecondsTable() {
        #expect(GoogleQuotaDecoding.windowSeconds(bucketID: "gemini-5h", window: nil) == 18000)
        #expect(GoogleQuotaDecoding.windowSeconds(bucketID: nil, window: "weekly") == 604_800)
        #expect(GoogleQuotaDecoding.windowSeconds(bucketID: nil, window: "daily") == 86400)
        #expect(GoogleQuotaDecoding.windowSeconds(bucketID: "x", window: "x") == nil)
    }
}
