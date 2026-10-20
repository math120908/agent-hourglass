import Foundation
import GRDB
import os

/// Accepts successful snapshots for history. `HistoryStore` conforms; the Poller holds an optional one.
public protocol HistoryRecording: Sendable {
    func record(_ snapshot: UsageSnapshot) async throws
}

extension HistoryStore: HistoryDeleting, HistoryRecording {
    /// Spec §8 write rule: a row only when percent/used/resets_at changes (spend: used/limit),
    /// or `heartbeat` seconds since the last row for the key. Duplicate ts is ignored.
    public func record(_ snapshot: UsageSnapshot) async throws {
        let account = snapshot.accountID.rawValue
        let ts = Int64(snapshot.fetchedAt.timeIntervalSince1970.rounded(.down))
        let cache = lastRows
        try await db.write { db in
            for m in snapshot.meters {
                let key = Self.meterKey(m)
                let row = LastRow(ts: ts, a: m.percentUsed, b: m.used, c: m.resetsAt.map { Int64($0.timeIntervalSince1970.rounded(.down)) })
                guard try cache.shouldWrite(row, key: "\(account)|\(key)", db: db, seed: {
                    try Row.fetchOne($0, sql: "SELECT ts, percent, used, resets_at FROM sample WHERE account_id = ? AND meter = ? ORDER BY ts DESC LIMIT 1", arguments: [account, key])
                }) else { continue }
                try db.execute(
                    sql: "INSERT OR IGNORE INTO sample (account_id, meter, ts, percent, used, limit_v, resets_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: [account, key, ts, m.percentUsed, m.used, m.limit, row.c]
                )
            }
            if let s = snapshot.spend {
                let row = LastRow(ts: ts, a: Double(s.usedMinor), b: s.limitMinor.map(Double.init), c: nil)
                guard try cache.shouldWrite(row, key: "\(account)|$spend", db: db, seed: {
                    try Row.fetchOne($0, sql: "SELECT ts, used_minor, limit_minor, NULL FROM spend_sample WHERE account_id = ? ORDER BY ts DESC LIMIT 1", arguments: [account])
                }) else { return }
                try db.execute(
                    sql: "INSERT OR IGNORE INTO spend_sample (account_id, ts, used_minor, limit_minor, currency, exponent) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [account, ts, s.usedMinor, s.limitMinor, s.currency, s.exponent]
                )
            }
        }
    }

    /// `Meter.Kind` raw value, plus `:<model>` for weeklyModel.
    static func meterKey(_ m: Meter) -> String {
        m.kind == .weeklyModel ? "\(m.kind.rawValue):\(m.label)" : m.kind.rawValue
    }
}

struct LastRow: Equatable, Sendable {
    var ts: Int64
    var a: Double?
    var b: Double?
    var c: Int64?
}

/// In-memory last-written row per `(account, meter)`, seeded from the DB on first use.
final class LastRowCache: Sendable {
    static let heartbeat: Int64 = 3600
    private let rows = OSAllocatedUnfairLock<[String: LastRow]>(initialState: [:])

    /// Called inside the write transaction, so check-and-set is serialized with the insert.
    func shouldWrite(_ new: LastRow, key: String, db: Database, seed: (Database) throws -> Row?) throws -> Bool {
        var last = rows.withLock { $0[key] }
        if last == nil, let r = try seed(db) {
            last = LastRow(ts: r[0], a: r[1], b: r[2], c: r[3])
        }
        if let last, last.a == new.a, last.b == new.b, last.c == new.c, new.ts - last.ts < Self.heartbeat {
            return false
        }
        rows.withLock { $0[key] = new }
        return true
    }

    func clear() { rows.withLock { $0.removeAll() } }
}
