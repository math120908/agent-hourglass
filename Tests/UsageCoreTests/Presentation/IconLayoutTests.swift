import Foundation
import Testing
@testable import UsageCore

@Suite struct IconLayoutTests {
    @Test func barFractionsClamp() {
        let l = InstrumentIconLayout(IconState(level: .critical, percent: 140, pace: nil, caption: "5H", weekly: -5))
        #expect(l.sessionFraction == 1)
        #expect(l.weeklyFraction == 0)
        #expect(InstrumentIconLayout(IconState(level: .normal, percent: 39, pace: nil, caption: "5H")).weeklyFraction == nil)
    }

    @Test func percentTextShownAlways() {
        #expect(InstrumentIconLayout(IconState(level: .normal, percent: 1, pace: nil, caption: "5H", weekly: 39)).text == "1%")
        #expect(InstrumentIconLayout(IconState(level: .critical, percent: 96, pace: nil, caption: "5H", weekly: 91)).text == "96%")
        #expect(InstrumentIconLayout(IconState(level: .outline, percent: 42, pace: nil, caption: "5H", weekly: 39)).text == "--")
    }

    @Test func outlineHasNoFill() {
        let l = InstrumentIconLayout(IconState(level: .outline, percent: 42, pace: 62, caption: "5H", weekly: 95))
        #expect(l.sessionFraction == nil && l.weeklyFraction == nil)
        #expect(l.dashed && l.isTemplate)
    }

    @Test func toneAndTemplate() {
        let n = InstrumentIconLayout(IconState(level: .normal, percent: 1, pace: nil, caption: "5H", weekly: 39))
        #expect(n.isTemplate)
        let w = InstrumentIconLayout(IconState(level: .normal, percent: 10, pace: nil, caption: "5H", weekly: 80))
        #expect(!w.isTemplate && w.sessionTone == .ink && w.weeklyTone == .warning)
    }

    @Test func weeklyFromSnapshot() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = AccountID(kind: .claude, remoteID: "a")
        let snap = UsageSnapshot(accountID: a, fetchedAt: now, plan: nil, meters: [
            Meter(kind: .session5h, label: "Session usage", percentUsed: 1, resetsAt: now.addingTimeInterval(3600), windowLength: .seconds(5 * 3600)),
            Meter(kind: .weeklyAll, label: "All models", percentUsed: 38.6, resetsAt: now.addingTimeInterval(86400), windowLength: .seconds(7 * 86400)),
        ], spend: nil)
        let s = IconState.make(appState: [a: snap], statuses: [:], menuBarAccount: nil, order: [a], now: now)
        #expect(s.weekly == 39)
    }
}
