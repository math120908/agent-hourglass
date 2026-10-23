import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

@MainActor
struct AppModelTests {
    private static let token = "tok-secret-fixture-123"

    private func make(now: Date = Date()) async throws -> (AppModel, UsageEnvironment) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: defaults), now: { now })
        return (model, env)
    }

    private func seed(_ env: UsageEnvironment, _ id: AccountID, name: String, fetchedAt: Date) async throws {
        _ = try await env.registry.load()
        try await env.registry.upsert(AccountEntry(id: id, kind: id.kind ?? .claude, displayName: name, remoteLogin: nil, order: 0, addedAt: fetchedAt, status: "ok"))
        try env.shared.cache.write(UsageSnapshot(accountID: id, fetchedAt: fetchedAt, meters: []))
    }

    @Test func testCachedStatus() {
        let now = Date()
        #expect(AppModel.cachedStatus(fetchedAt: now.addingTimeInterval(-59), now: now, interval: .seconds(60)) == .fresh)
        #expect(AppModel.cachedStatus(fetchedAt: now.addingTimeInterval(-121), now: now, interval: .seconds(60)) == .stale)
    }

    @Test func testLoadSeedsFromCache() async throws {
        let now = Date()
        let (model, env) = try await make(now: now)
        let id = AccountID(kind: .claude, remoteID: "a")
        try await seed(env, id, name: "Snorlax", fetchedAt: now.addingTimeInterval(-10))
        await model.load()
        #expect(model.entries.map(\.id) == [id])
        #expect(model.appState.snapshots[id]?.accountID == id)
        #expect(model.appState.statuses[id] == .fresh)
        #expect(model.appState.names[id] == "Snorlax")
    }

    @Test func testRemoveDeletesCacheFile() async throws {
        let (model, env) = try await make()
        let id = AccountID(kind: .codex, remoteID: "r")
        try await seed(env, id, name: "x", fetchedAt: Date())
        await model.load()
        try await model.remove(id)
        #expect(env.shared.cache.read(id) == nil)
        #expect(model.entries.isEmpty)
        #expect(model.appState.snapshots[id] == nil)
        #expect(!model.appState.accounts.contains(id))
    }

    @Test func testResultForRemovedAccountIgnored() async throws {
        let (model, env) = try await make()
        let id = AccountID(kind: .claude, remoteID: "gone")
        try await seed(env, id, name: "x", fetchedAt: Date())
        await model.load()
        try await model.remove(id)
        // A fetch in flight at removal time wrote the cache and then reports success.
        let snap = UsageSnapshot(accountID: id, fetchedAt: Date(), meters: [])
        try env.shared.cache.write(snap)
        model.deliver(id, .success(snap))
        #expect(model.appState.snapshots[id] == nil)
        #expect(env.shared.cache.read(id) == nil)
    }

    @Test func testHandleURL() async throws {
        let (model, env) = try await make()
        let id = AccountID(kind: .claude, remoteID: "u@x")
        try await seed(env, id, name: "x", fetchedAt: Date())
        await model.load()
        model.handle(url: URL(string: "agenthourglass://settings?id=claude:u")!)
        #expect(model.focusedAccount == nil)
        model.handle(url: DeepLink.url(for: AccountID(kind: .claude, remoteID: "other")))
        #expect(model.focusedAccount == nil)
        model.handle(url: DeepLink.url(for: id))
        #expect(model.focusedAccount == id)
    }

    @Test func testDeepLinkRoundTrip() {
        let id = AccountID(rawValue: "claude:a:b@c")!
        #expect(DeepLink.accountID(from: DeepLink.url(for: id)) == id)
        #expect(DeepLink.accountID(from: URL(string: "https://account?id=claude:a")!) == nil)
        #expect(DeepLink.accountID(from: URL(string: "agenthourglass://account/claude:a")!) == nil)
    }

    @Test func testDiagnosticsHasNoNames() async throws {
        let (model, env) = try await make()
        let id = AccountID(kind: .claude, remoteID: "diag-\(UUID())")
        try await seed(env, id, name: "Snorlax", fetchedAt: Date())
        let cred = Credential(kind: .claude, access: Secret(Self.token), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
        try env.store.write(cred, for: id, label: "Snorlax")
        defer { try? env.store.delete(id) }
        await model.load()
        let report = model.diagnosticsReport()
        #expect(report.contains("accounts: 1"))
        #expect(!report.contains("Snorlax"))
        #expect(!report.contains(Self.token))
        #expect(!report.contains(id.rawValue))
    }
}
