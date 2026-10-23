import XCTest
import WidgetKit
import UsageCore

final class TimelineBuilderTests: XCTestCase {
    typealias F = WidgetFixtures
    let entry = AccountEntry(id: AccountID(rawValue: "claude:max")!, kind: .claude, displayName: "Max", remoteLogin: nil, order: 0, addedAt: F.now, status: "ok")

    func input(_ snapshot: UsageSnapshot? = F.claudeMax, status: AccountStatus? = .fresh, keys: [String] = []) -> TimelineInput {
        TimelineInput(
            account: entry,
            snapshot: snapshot,
            status: status,
            meterKeys: keys.compactMap(MeterKey.init(rawValue:)),
            settings: .default,
            theme: .glass,
            family: .small
        )
    }

    func testEntriesCarryInputAndPlanDates() {
        let i = input(keys: ["session5h"])
        let entries = TimelineBuilder.entries(i, now: F.now)
        let reset = F.claudeMax.meters[0].resetsAt!
        let expected = TimelinePlan.entryDates(now: F.now, resets: [reset], staleAt: F.now.addingTimeInterval(WidgetFreshness.staleAfter))
        XCTAssertEqual(entries.map(\.date), expected)
        for e in entries {
            XCTAssertEqual(e.account, entry)
            XCTAssertEqual(e.snapshot, F.claudeMax)
            XCTAssertEqual(e.status, .fresh)
            XCTAssertEqual(e.meterKeys, i.meterKeys)
            XCTAssertEqual(e.settings, .default)
            XCTAssertEqual(e.theme, .glass)
        }
    }

    func testEntryDatesIncludeResetOfResolvedMetersOnly() {
        let dates = TimelineBuilder.entries(input(keys: ["session5h"]), now: F.now).map(\.date)
        XCTAssertTrue(dates.contains(F.claudeMax.meters[0].resetsAt!))
        XCTAssertFalse(dates.contains(F.claudeMax.meters[1].resetsAt!))
    }

    func testStaleDateBeatsGridDateWithin60s() {
        // fetchedAt 30 s after now: staleAt lands 30 s after the 1800 s grid date.
        let s = UsageSnapshot(accountID: F.claudeMax.accountID, fetchedAt: F.now.addingTimeInterval(30), meters: [])
        let dates = TimelineBuilder.entries(input(s), now: F.now).map(\.date)
        XCTAssertTrue(dates.contains(F.now.addingTimeInterval(1830)))
        XCTAssertFalse(dates.contains(F.now.addingTimeInterval(1800)))
    }

    func provider(timeout: TimeInterval = 20, fetch: @escaping @Sendable (AccountID) async -> (UsageSnapshot?, AccountStatus?)) -> UsageTimelineProvider {
        let e = entry
        return UsageTimelineProvider(
            fetch: fetch,
            cacheRead: { _ in F.claudeMax },
            loadEntries: { [e] },
            loadSettings: { (.default, .glass) },
            now: { F.now },
            timeout: timeout
        )
    }

    func testConfiguredAccountMissingGivesEmptyEntry() async {
        var intent = SelectAccountMetersIntent()
        intent.account = AccountEntity(id: "claude:gone", name: "Gone", kind: .claude)
        let t = await provider { _ in (F.claudeMax, .fresh) }.makeTimeline(intent: intent, family: .small)
        XCTAssertEqual(t.entries.count, 1)
        XCTAssertNil(t.entries[0].account)
        XCTAssertNil(t.entries[0].snapshot)
        XCTAssertEqual(t.reload, TimelinePlan.reloadDate(now: F.now))
    }

    func testFetchFailureUsesCachedSnapshotWithStatus() async {
        let t = await provider { _ in (F.claudeMax, .needsLogin) }.makeTimeline(intent: SelectAccountMetersIntent(), family: .small)
        XCTAssertFalse(t.entries.isEmpty)
        XCTAssertTrue(t.entries.allSatisfy { $0.snapshot == F.claudeMax && $0.status == .needsLogin })
    }

    func testFetchTimeoutFallsBackToCache() async {
        let start = Date()
        let t = await provider(timeout: 0.1) { _ in
            try? await Task.sleep(for: .seconds(30))
            return (nil, .offline)
        }.makeTimeline(intent: SelectAccountMetersIntent(), family: .small)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(t.entries.first?.snapshot, F.claudeMax)
        XCTAssertNil(t.entries.first?.status)
    }

    func testPolicyIsAfter15Min() async {
        let t = await provider { _ in (F.claudeMax, .fresh) }.makeTimeline(intent: SelectAccountMetersIntent(), family: .small)
        XCTAssertEqual(t.reload, F.now.addingTimeInterval(900))
    }
}
