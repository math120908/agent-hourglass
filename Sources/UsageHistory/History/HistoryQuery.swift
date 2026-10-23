import UsageCore
import Foundation
import GRDB

/// Read side of the history store (spec §10.7): raw rows inside the raw window, hourly rollups before it.
public struct HistoryQuery: Sendable {
    public static let heartbeat: TimeInterval = 3600
    public static let rawWindow: TimeInterval = 90 * 86400

    let store: HistoryStore
    let now: @Sendable () -> Date

    public init(store: HistoryStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    struct Row_: Equatable, Sendable { var ts: Int64; var percent: Double?; var peak: Double?; var resets: Int64? }

    /// Rows for every meter in `[range.start, range.end]`, led by the last row before the start
    /// (moved to the start) so step lines begin at the range edge.
    func rows(account: AccountID, range: DateInterval) async throws -> [String: [Row_]] {
        let lo = Int64(range.start.timeIntervalSince1970.rounded(.down))
        let hi = Int64(range.end.timeIntervalSince1970.rounded(.down))
        let cutoff = Int64((now().timeIntervalSince1970 - Self.rawWindow).rounded(.down))
        let sql = """
            SELECT meter, ts, percent, percent AS peak, resets_at FROM sample
              WHERE account_id = :a AND ts >= :cut AND ts <= :hi
            UNION ALL
            SELECT meter, hour, percent_last, percent_max, resets_at_last FROM sample_hourly
              WHERE account_id = :a AND hour < :cut AND hour <= :hi
            ORDER BY 1, 2
            """
        let all = try await store.db.read { db in
            try Row.fetchAll(db, sql: sql, arguments: ["a": account.rawValue, "cut": cutoff, "hi": hi]).map { r in
                (r[0] as String, Row_(ts: r[1], percent: r[2], peak: r[3], resets: r[4]))
            }
        }
        var out: [String: [Row_]] = [:]
        for (meter, row) in all {
            var list = out[meter, default: []]
            if row.ts < lo {
                list = [Row_(ts: lo, percent: row.percent, peak: row.percent, resets: row.resets)]
            } else {
                list.append(row)
            }
            out[meter] = list
        }
        return out
    }

    public func series(account: AccountID, range: DateInterval, maxPoints: Int = 500) async throws -> [Series] {
        let byMeter = try await rows(account: account, range: range)
        var result: [Series] = []
        for meter in byMeter.keys.sorted() {
            var current: [Row_] = []
            func flush() {
                guard let first = current.first else { return }
                let id = "\(meter)@\(first.resets.map(String.init) ?? "-")"
                result.append(Series(id: id, meter: meter, points: Self.downsample(Self.withGaps(current), max: maxPoints)))
                current = []
            }
            for r in byMeter[meter]! {
                if let last = current.last, last.resets != r.resets { flush() }
                current.append(r)
            }
            flush()
        }
        return result
    }

    static func withGaps(_ rows: [Row_]) -> [SeriesPoint] {
        var pts: [SeriesPoint] = []
        for r in rows {
            if let prev = pts.last, TimeInterval(r.ts) - prev.t.timeIntervalSince1970 > 3 * heartbeat {
                pts.append(SeriesPoint(t: prev.t.addingTimeInterval(heartbeat), percent: nil))
            }
            pts.append(SeriesPoint(t: Date(timeIntervalSince1970: TimeInterval(r.ts)), percent: r.percent))
        }
        return pts
    }

    /// Min/max bucketing: keeps first, last, every gap marker, and each bucket's extremes (peaks survive).
    static func downsample(_ pts: [SeriesPoint], max: Int) -> [SeriesPoint] {
        guard pts.count > max, max >= 4 else { return pts }
        let inner = Array(pts[1..<(pts.count - 1)])
        let buckets = (max - 2) / 2
        let size = Double(inner.count) / Double(buckets)
        var out = [pts[0]]
        for b in 0..<buckets {
            let slice = inner[Int(Double(b) * size)..<min(inner.count, Int(Double(b + 1) * size))]
            if let gap = slice.first(where: { $0.percent == nil }) { out.append(gap); continue }
            guard let lo = slice.min(by: { $0.percent! < $1.percent! }),
                  let hi = slice.max(by: { $0.percent! < $1.percent! }) else { continue }
            out += lo.t <= hi.t ? [lo, hi] : [hi, lo]
            if lo == hi { out.removeLast() }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    public func summary(account: AccountID, range: DateInterval) async throws -> RangeSummary {
        let byMeter = try await rows(account: account, range: range)
        let session = byMeter[Meter.Kind.session5h.rawValue] ?? []
        let peaks = session.compactMap(\.peak)
        var windowPeak: [Int64?: Double] = [:]
        for r in session { if let p = r.peak { windowPeak[r.resets] = Swift.max(windowPeak[r.resets] ?? 0, p) } }
        return RangeSummary(
            peakSession: peaks.max(),
            windowsOver90: windowPeak.values.filter { $0 >= 90 }.count,
            weeklyAtEnd: byMeter[Meter.Kind.weeklyAll.rawValue]?.last?.percent
        )
    }
}
