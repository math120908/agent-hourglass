import UsageCore
import Foundation
import GRDB

public enum ExportFormat: String, Sendable { case csv, json }

/// One exported sample (spec §11). Tokens never reach this type: it is built from history rows only.
struct ExportRow: Sendable {
    var meter: String
    var ts: Int64
    var percent: Double?
    var used: String?
    var limit: String?
    var unit: String?
    var resetsAt: Int64?
    var hourly: Bool
}

/// Spec §11 export: CSV or JSON, per account and per meter, written 0600 via `AppSupport.secureWrite`.
public struct Exporter: Sendable {
    public static let csvHeader = "account_id,account_name,provider,meter,timestamp,percent,used,limit,unit,resets_at"

    let store: HistoryStore
    let now: @Sendable () -> Date

    public init(store: HistoryStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func export(format: ExportFormat, accounts: [AccountEntry], range: DateInterval?, to url: URL, appVersion: String) async throws {
        let data: Data
        switch format {
        case .csv: data = try await csv(accounts: accounts, range: range)
        case .json: data = try await json(accounts: accounts, range: range, appVersion: appVersion)
        }
        try AppSupport.secureWrite(data, to: url)
    }

    func csv(accounts: [AccountEntry], range: DateInterval?) async throws -> Data {
        var out = Self.csvHeader + "\r\n"
        for a in accounts {
            let prefix = [a.id.rawValue, a.displayName, a.kind.rawValue].map(Self.csvField).joined(separator: ",")
            try await forEachRow(account: a.id, range: range) { r in
                let fields = [
                    r.meter, Self.iso(r.ts), r.percent.map(Self.num) ?? "",
                    r.used ?? "", r.limit ?? "", r.unit ?? "", r.resetsAt.map(Self.iso) ?? "",
                ]
                out += prefix + "," + fields.map(Self.csvField).joined(separator: ",") + "\r\n"
            }
        }
        return Data(out.utf8)
    }

    /// Meter rows (raw + hourly, ordered by meter then time), then spend rows. Iterates GRDB cursors.
    func forEachRow(account: AccountID, range: DateInterval?, _ body: (ExportRow) throws -> Void) async throws {
        let lo = range.map { Int64($0.start.timeIntervalSince1970.rounded(.down)) } ?? Int64.min
        let hi = range.map { Int64($0.end.timeIntervalSince1970.rounded(.down)) } ?? Int64.max
        let args: StatementArguments = ["a": account.rawValue, "lo": lo, "hi": hi]
        let rows: [ExportRow] = try await store.db.read { db in
            var acc: [ExportRow] = []
            let meters = try Row.fetchCursor(db, sql: """
                SELECT meter, ts, percent, used, limit_v, resets_at, 0 FROM sample
                  WHERE account_id = :a AND ts BETWEEN :lo AND :hi
                UNION ALL
                SELECT meter, hour, percent_last, NULL, NULL, resets_at_last, 1 FROM sample_hourly
                  WHERE account_id = :a AND hour BETWEEN :lo AND :hi
                ORDER BY 1, 2, 7
                """, arguments: args)
            while let r = try meters.next() {
                acc.append(ExportRow(
                    meter: r[0], ts: r[1], percent: r[2],
                    used: (r[3] as Double?).map(Self.num), limit: (r[4] as Double?).map(Self.num),
                    unit: nil, resetsAt: r[5], hourly: (r[6] as Int) == 1))
            }
            let spend = try Row.fetchCursor(db, sql: """
                SELECT ts, used_minor, limit_minor, currency, exponent FROM spend_sample
                  WHERE account_id = :a AND ts BETWEEN :lo AND :hi ORDER BY ts
                """, arguments: args)
            while let r = try spend.next() {
                let exp: Int = r[4] ?? 0
                acc.append(ExportRow(
                    meter: "spend", ts: r[0], percent: nil,
                    used: (r[1] as Int64?).map { Self.major($0, exp) },
                    limit: (r[2] as Int64?).map { Self.major($0, exp) },
                    unit: r[3], resetsAt: nil, hourly: false))
            }
            return acc
        }
        for r in rows { try body(r) }
    }

    // MARK: formatting

    static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func iso(_ ts: Int64) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    static func num(_ d: Double) -> String {
        if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    /// Minor units to a major-unit decimal string without float error (850, 3 -> "0.85").
    static func major(_ minor: Int64, _ exponent: Int) -> String {
        var d = Decimal(minor)
        for _ in 0..<max(exponent, 0) { d /= 10 }
        return "\(d)"
    }
}
