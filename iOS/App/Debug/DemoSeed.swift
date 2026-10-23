#if DEBUG
import Foundation
import UsageCore

/// Debug-only fake Claude account for headless checks. Never touches real accounts.
enum DemoSeed {
    static let remoteID = "demo-0001"
    private static let id = AccountID(kind: .claude, remoteID: remoteID)

    static func seed(_ env: UsageEnvironment) async throws {
        _ = try await env.registry.load()
        try await env.registry.upsert(AccountEntry(id: id, kind: .claude, displayName: "Demo", remoteLogin: nil, order: 0, addedAt: .now, status: "ok"))
        let cred = Credential(kind: .claude, access: Secret("demo-not-a-token"), refresh: nil, expiresAt: .distantFuture, refreshExpiresAt: nil, scopes: [])
        try env.store.write(cred, for: id, label: "Agent Hourglass demo")
        let meters = [
            Meter(kind: .session5h, label: "Session", percentUsed: 25),
            Meter(kind: .weeklyAll, label: "Weekly", percentUsed: 60),
        ]
        try env.shared.cache.write(UsageSnapshot(accountID: id, fetchedAt: .now, plan: "demo", meters: meters))
    }

    /// Removes registry entry, Keychain item and snapshot; a missing piece is not an error.
    static func clear(_ env: UsageEnvironment) async throws {
        _ = try await env.registry.load()
        do {
            try await env.registry.remove(id)
        } catch AccountRegistryError.unknownAccount {}
        try env.store.delete(id)
        try env.shared.cache.remove(id)
    }
}
#endif
