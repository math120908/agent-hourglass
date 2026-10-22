import Foundation
import os

/// One-time move from the old `cc.kuoc.claude-usage` identifier. Every step is idempotent and never
/// deletes source data unless the copy was verified.
public enum LegacyMigration {
    public static let oldID = "cc.kuoc.claude-usage"
    public static let defaultsFlag = "migratedFromClaudeUsage"
    public static let keychainFlag = "migratedKeychainFromClaudeUsage"
    public static let launchAtLoginKey = "launchAtLogin"
    private static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "Migration")

    public enum DirOutcome: Equatable, Sendable { case noLegacy, alreadyPresent, moved, failed }

    /// Moves `<base>/cc.kuoc.claude-usage` to `<base>/cc.kuoc.agent-hourglass` when only the old one exists.
    @discardableResult
    public static func migrateDirectory(base: URL? = nil) -> DirOutcome {
        let fm = FileManager.default
        guard let root = try? base ?? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            log.error("dir: no base"); return .failed
        }
        let old = root.appendingPathComponent(oldID, isDirectory: true)
        let new = root.appendingPathComponent(AppSupport.folderName, isDirectory: true)
        let outcome: DirOutcome
        if !fm.fileExists(atPath: old.path) {
            outcome = .noLegacy
        } else if fm.fileExists(atPath: new.path) {
            outcome = .alreadyPresent
        } else {
            do {
                try fm.moveItem(at: old, to: new)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: new.path)
                outcome = .moved
            } catch {
                log.error("dir move failed: \(String(describing: error), privacy: .public)")
                return .failed
            }
        }
        log.info("dir \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    /// Copies keys missing from `target` out of the old domain, once.
    @discardableResult
    public static func migrateDefaults(old: [String: Any]?, target: UserDefaults) -> Int {
        guard !target.bool(forKey: defaultsFlag) else { return 0 }
        var copied = 0
        for (k, v) in old ?? [:] where target.object(forKey: k) == nil {
            target.set(v, forKey: k)
            copied += 1
        }
        target.set(true, forKey: defaultsFlag)
        log.info("defaults copied=\(copied, privacy: .public)")
        return copied
    }

    public struct KeychainResult: Equatable, Sendable {
        public var moved = 0, alreadyNew = 0, absent = 0, failed = 0
        public init() {}
    }

    /// For each account: old item -> new store, read back, then delete the old item. A failed or denied
    /// read leaves the old item alone; the account then shows "needs sign-in". Runs once (flag).
    public static func migrateKeychain(
        ids: [AccountID],
        old: CredentialStoring,
        new: CredentialStoring,
        label: (AccountID) -> String,
        defaults: UserDefaults
    ) -> KeychainResult {
        var r = KeychainResult()
        guard !ids.isEmpty, !defaults.bool(forKey: keychainFlag) else { return r }
        defer { defaults.set(true, forKey: keychainFlag) }
        for id in ids {
            if (try? new.read(id)) ?? nil != nil { r.alreadyNew += 1; continue }
            let cred: Credential
            do {
                guard let c = try old.read(id) else { r.absent += 1; continue }
                cred = c
            } catch {
                log.error("keychain read old failed: \(String(describing: error), privacy: .public)")
                r.failed += 1; continue
            }
            do {
                try new.write(cred, for: id, label: label(id))
                guard let back = try new.read(id), back.access == cred.access else { r.failed += 1; continue }
                try old.delete(id)
                r.moved += 1
            } catch {
                log.error("keychain write/verify failed: \(String(describing: error), privacy: .public)")
                r.failed += 1
            }
        }
        log.info("keychain moved=\(r.moved, privacy: .public) alreadyNew=\(r.alreadyNew, privacy: .public) absent=\(r.absent, privacy: .public) failed=\(r.failed, privacy: .public)")
        return r
    }
}
