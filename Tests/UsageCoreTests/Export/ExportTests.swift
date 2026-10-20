import Foundation
import GRDB
import Testing
@testable import UsageCore

@Suite struct ExportTests {
    let t0: Int64 = 1_800_000_000
    let acct = AccountEntry(
        id: AccountID(rawValue: "claude:ACCOUNT")!, kind: .claude, displayName: "Personal Max",
        remoteLogin: nil, order: 0, addedAt: Date(timeIntervalSince1970: 0), status: "ok")

    private func seeded() async throws -> Exporter {
        let s = try HistoryStore.inMemory()
        let a = acct.id.rawValue
        let t0 = t0
        try await s.db.write { db in
            try db.execute(sql: "INSERT INTO sample VALUES (?, 'session5h', ?, 42, NULL, NULL, ?)", arguments: [a, t0, t0 + 18000])
            try db.execute(sql: "INSERT INTO sample VALUES (?, 'session5h', ?, 57.5, NULL, NULL, ?)", arguments: [a, t0 + 600, t0 + 18000])
            try db.execute(sql: "INSERT INTO sample VALUES (?, 'weeklyAll', ?, 12, NULL, NULL, NULL)", arguments: [a, t0])
            try db.execute(sql: "INSERT INTO sample_hourly VALUES (?, 'session5h', ?, 90, 30, ?)", arguments: [a, t0 - 3600, t0])
            try db.execute(sql: "INSERT INTO spend_sample VALUES (?, ?, 85, 2000, 'EUR', 2)", arguments: [a, t0 + 60])
        }
        let n = Date(timeIntervalSince1970: TimeInterval(t0 + 86400))
        return Exporter(store: s, now: { n })
    }

    private func golden(_ ext: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: "export-golden", withExtension: ext, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func run(_ e: Exporter, _ f: ExportFormat, _ accounts: [AccountEntry], range: DateInterval? = nil) async throws -> (String, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("out.\(f.rawValue)")
        try await e.export(format: f, accounts: accounts, range: range, to: url, appVersion: "1.0 (abc1234)")
        return (try String(contentsOf: url, encoding: .utf8), url)
    }

    @Test func csvGolden() async throws {
        let (out, _) = try await run(seeded(), .csv, [acct])
        #expect(out == (try golden("csv")))
    }

    @Test func jsonGolden() async throws {
        let (out, _) = try await run(seeded(), .json, [acct])
        #expect(out == (try golden("json")))
        _ = try JSONSerialization.jsonObject(with: Data(out.utf8))
    }

    @Test func hourlyMarkedRollup() async throws {
        let (out, _) = try await run(seeded(), .json, [acct])
        let obj = try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let accts = try #require(obj["accounts"] as? [[String: Any]])
        let session = try #require((accts[0]["series"] as? [String: Any])?["session5h"] as? [[String: Any]])
        #expect(session.first?["rollup"] as? String == "hourly")
        #expect(session.dropFirst().allSatisfy { $0["rollup"] == nil })
    }

    @Test func csvQuotesNames() async throws {
        var a = acct
        a.displayName = "Work, \"Team\"\nMax"
        let (out, _) = try await run(seeded(), .csv, [a])
        #expect(out.contains("claude:ACCOUNT,\"Work, \"\"Team\"\"\nMax\",claude,session5h,"))
    }

    @Test func rangeFilterAndEmpty() async throws {
        let e = try await seeded()
        let far = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 60)
        let (out, _) = try await run(e, .csv, [acct], range: far)
        #expect(out == Exporter.csvHeader + "\r\n")
    }

    @Test func exportFile0600() async throws {
        let (_, url) = try await run(seeded(), .csv, [acct])
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
