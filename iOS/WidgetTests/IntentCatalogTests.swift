import XCTest
import UsageCore

final class IntentCatalogTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    func entry(_ id: String, _ kind: ProviderKind, order: Int) -> AccountEntry {
        AccountEntry(id: AccountID(rawValue: id)!, kind: kind, displayName: "n\(order)", remoteLogin: nil, order: order, addedAt: date, status: "ok")
    }

    var entries: [AccountEntry] { [entry("codex:b", .codex, order: 1), entry("claude:x", .claude, order: 0)] }

    func testAccountsInRegistryOrder() {
        XCTAssertEqual(AccountCatalog.entities(entries).map(\.id), ["claude:x", "codex:b"])
        XCTAssertEqual(AccountCatalog.entities(entries).first?.kind, .claude)
    }

    func testNilAccountResolvesToFirst() {
        XCTAssertEqual(AccountCatalog.resolve(nil, in: entries)?.id.rawValue, "claude:x")
        XCTAssertEqual(AccountCatalog.resolve("codex:b", in: entries)?.id.rawValue, "codex:b")
    }

    func testRemovedAccountResolvesToNil() {
        XCTAssertNil(AccountCatalog.resolve("claude:gone", in: entries))
    }

    func testMeterCatalogFromSnapshot() {
        let claudeMax = UsageSnapshot(accountID: AccountID(rawValue: "claude:x")!, fetchedAt: date, meters: [
            Meter(kind: .session5h, label: "5-hour", percentUsed: 10),
            Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 20),
            Meter(kind: .weeklyModel, label: "Opus", percentUsed: 30),
        ])
        let meters = MeterCatalog.meters(for: entries[1], snapshot: claudeMax)
        XCTAssertEqual(meters.map(\.id), ["claude:x|session5h", "claude:x|weeklyAll", "claude:x|weeklyModel:Opus"])
        XCTAssertEqual(meters.map(\.label), ["5-hour", "Weekly", "Opus"])
    }

    func testMeterCatalogWithoutSnapshotUsesDefaults() {
        XCTAssertEqual(MeterCatalog.meters(for: entries[1], snapshot: nil).map(\.label), ["5-hour", "Weekly"])
        let codex = MeterCatalog.meters(for: entries[0], snapshot: nil)
        XCTAssertEqual(codex.map(\.label), ["5-hour", "Weekly"])
        XCTAssertEqual(codex.map(\.key.rawValue), ["window:18000", "window:604800"])
        let copilot = MeterCatalog.meters(for: entry("copilot:c", .copilot, order: 2), snapshot: nil)
        XCTAssertEqual(copilot.map(\.label), ["Premium requests"])
    }

    func testMeterEntityIdRoundTrip() {
        let account = AccountID(rawValue: "claude:org:abc")!
        let key = MeterKey(rawValue: "weeklyModel:Opus")!
        let id = MeterEntity.makeID(account: account, key: key)
        let parsed = MeterEntity.parseID(id)
        XCTAssertEqual(parsed?.account, account)
        XCTAssertEqual(parsed?.key, key)
        XCTAssertNil(MeterEntity.parseID("no-separator"))
    }
}
