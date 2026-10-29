import Foundation
import Testing
@testable import UsageCore

struct ResetRadarLogicTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func event(_ day: String, _ kind: ResetEvent.Kind = .reset, confirmed: Bool = true, at: Date? = nil, id: String? = nil) -> ResetEvent {
        ResetEvent(id: id ?? "\(day)-\(kind)-\(confirmed)", day: day, kind: kind, summary: "s", url: nil, at: at, confirmed: confirmed)
    }

    @Test func decodeFixture() throws {
        let events = try ResetRadarLogic.decode(try fixture("codex-reset-timeline"))
        #expect(events.count == 12)
        let first = try #require(events.first)
        #expect(first.kind == .reset)
        #expect(first.day == "2026-10-28")
        #expect(first.confirmed)
        #expect(first.url?.host == "x.com")
        #expect(first.at == ISO8601DateFormatter().date(from: "2026-10-28T06:35:38Z"))
        #expect(events.filter { $0.kind == .credits }.count == 2)
    }

    @Test func decodeRejectsNonObject() {
        #expect(throws: ProviderError.self) { try ResetRadarLogic.decode(Data("[]".utf8)) }
        #expect(throws: ProviderError.self) { try ResetRadarLogic.decode(Data(#"{"x":1}"#.utf8)) }
    }

    @Test func decodeSkipsUnknownAndTolerantOfNulls() throws {
        let body = #"""
        {"events":[
          {"id":"a","date":"2026-10-01","type":"announcement","summary":"x","confirmed":true},
          {"id":"b","date":"2026-10-02","type":"reset","summary":"y","url":null,"announced_at":null,"observed_at":null,"confirmed":false},
          {"id":"c","date":"2026-10-03","type":"credits","summary":"z","observed_at":"2026-10-03T01:02:03Z","confirmed":true}
        ]}
        """#
        let events = try ResetRadarLogic.decode(Data(body.utf8))
        #expect(events.map(\.id) == ["b", "c"])
        #expect(events[0].url == nil && events[0].at == nil && !events[0].confirmed)
        #expect(events[1].at == ISO8601DateFormatter().date(from: "2026-10-03T01:02:03Z"))
    }

    @Test func summaryDecodesEntities() throws {
        let body = #"{"events":[{"id":"a","date":"2026-10-01","type":"reset","summary":"A &amp; B\n\nC","confirmed":true}]}"#
        let summary = try ResetRadarLogic.decode(Data(body.utf8)).first?.summary
        #expect(summary == "A & B C")
    }

    @Test func mergeCollapsesLiveAndObserved() throws {
        let events = try ResetRadarLogic.decode(try fixture("codex-reset-timeline"))
        let merged = ResetRadarLogic.merged(events)
        #expect(merged.count == 5)
        #expect(merged.map(\.day) == ["2026-10-28", "2026-10-26", "2026-10-25", "2026-10-23", "2026-10-22"])
        #expect(merged.allSatisfy { $0.confirmed })
        #expect(Set(merged.map(\.dedupeKey)).count == 5)
        let all = ResetRadarLogic.merged(events, limit: 100)
        #expect(all.count == 8)
        #expect(all.filter { $0.kind == .credits }.count == 1)
        let ats = all.compactMap(\.at)
        #expect(ats == ats.sorted(by: >))
    }

    @Test func firstRunSeedsWithoutNotifying() throws {
        let events = try ResetRadarLogic.decode(try fixture("codex-reset-timeline"))
        let r = ResetRadarLogic.pending(events, seen: nil, includeCredits: true)
        #expect(r.notify.isEmpty)
        #expect(r.seen == Set(events.filter(\.confirmed).map(\.dedupeKey)))
    }

    @Test func notifiesOnceForSameDay() {
        let old = [Self.event("2026-10-27")]
        let seen = ResetRadarLogic.pending(old, seen: nil, includeCredits: false).seen
        let live = Self.event("2026-10-28", confirmed: false)
        let r1 = ResetRadarLogic.pending(old + [live], seen: seen, includeCredits: false)
        #expect(r1.notify.isEmpty)
        let observed = Self.event("2026-10-28", confirmed: true)
        let observed2 = Self.event("2026-10-28", confirmed: true, id: "dup")
        let r2 = ResetRadarLogic.pending(old + [live, observed, observed2], seen: r1.seen, includeCredits: false)
        #expect(r2.notify.count == 1)
        #expect(r2.notify.first?.dedupeKey == "reset|2026-10-28")
        let r3 = ResetRadarLogic.pending(old + [live, observed], seen: r2.seen, includeCredits: false)
        #expect(r3.notify.isEmpty)
    }

    @Test func creditsGatedByToggle() {
        let seen: Set<String> = []
        let credits = Self.event("2026-10-28", .credits)
        let off = ResetRadarLogic.pending([credits], seen: seen, includeCredits: false)
        #expect(off.notify.isEmpty)
        #expect(off.seen.contains("credits|2026-10-28"))
        let on = ResetRadarLogic.pending([credits], seen: seen, includeCredits: true)
        #expect(on.notify.count == 1)
        #expect(ResetRadarLogic.pending([credits], seen: off.seen, includeCredits: true).notify.isEmpty)
    }

    @Test func lastResetCaption() {
        func caption(_ ago: TimeInterval) -> String? {
            ResetRadarLogic.lastResetCaption([Self.event("d", at: Self.now.addingTimeInterval(-ago))], now: Self.now)
        }
        #expect(caption(30 * 60) == "Last reset just now")
        #expect(caption(5 * 3600) == "Last reset 5h ago")
        #expect(caption(38 * 3600) == "Last reset 1d ago")
        let none = [Self.event("d", confirmed: false, at: Self.now), Self.event("e", .credits, at: Self.now)]
        #expect(ResetRadarLogic.lastResetCaption(none, now: Self.now) == nil)
    }
}
