import Foundation
import OSLog
import UsageCore

/// One plain-text status line per registered account, shown by the P3 shell.
struct ShellStatusLine: Equatable, Sendable {
    let id: AccountID
    let name: String
    let kind: ProviderKind
    let snapshotAge: TimeInterval?
    let hasCredential: Bool
    var text: String
}

enum ShellStatus {
    private static let logger = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Shell")

    static func lines(entries: [AccountEntry], cache: SnapshotCache, credentialIDs: Set<AccountID>, now: Date) -> [ShellStatusLine] {
        entries.sorted { $0.order < $1.order }.map { e in
            let age = cache.read(e.id).map { now.timeIntervalSince($0.fetchedAt) }
            let key = credentialIDs.contains(e.id)
            let text = "\(e.displayName) | \(e.kind.rawValue) | \(ageText(age)) | key \(key ? "yes" : "no")"
            return ShellStatusLine(id: e.id, name: e.displayName, kind: e.kind, snapshotAge: age, hasCredential: key, text: text)
        }
    }

    static func load(_ env: UsageEnvironment, now: Date) async -> [ShellStatusLine] {
        let entries = (try? await env.registry.load()) ?? []
        let ids = Set((try? env.store.allAccountIDs()) ?? [])
        return lines(entries: entries, cache: env.shared.cache, credentialIDs: ids, now: now)
    }

    /// Counts only; never names, ids or tokens.
    static func log(_ lines: [ShellStatusLine], process: String) {
        let snapshots = lines.filter { $0.snapshotAge != nil }.count
        let keys = lines.filter(\.hasCredential).count
        logger.notice("shell process=\(process, privacy: .public) accounts=\(lines.count, privacy: .public) snapshots=\(snapshots, privacy: .public) keychain=\(keys, privacy: .public)")
    }

    private static func ageText(_ age: TimeInterval?) -> String {
        guard let age else { return "no snapshot" }
        let s = max(0, Int(age))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
