import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private let testService = "cc.kuoc.agent-hourglass.ios-tests"

private func makeTestEnv() throws -> (UsageEnvironment, URL) {
    let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let env = try UsageEnvironment.make(base: tmp, service: testService, accessGroup: AppGroup.keychainAccessGroup)
    return (env, tmp)
}

@Test func makePlacesEverythingUnderTheBase() throws {
    let (env, tmp) = try makeTestEnv()
    #expect(env.directory.path == tmp.appending(path: "cc.kuoc.agent-hourglass").path)
    #expect(env.registry.url == env.directory.appending(path: "accounts.json"))
}

@Test func testStoreUsesTestService() throws {
    let (env, _) = try makeTestEnv()
    #expect(env.store.service == testService)
}

@Test func keychainRoundTripWithAccessGroup() throws {
    let (env, _) = try makeTestEnv()
    let id = AccountID(kind: .claude, remoteID: "test-\(UUID())")
    let cred = Credential(kind: .claude, access: Secret("t-not-a-token"), refresh: nil, expiresAt: nil, refreshExpiresAt: nil, scopes: [])
    try env.store.write(cred, for: id, label: "test")
    #expect(try env.store.read(id) == cred)
    #expect(try env.store.allAccountIDs().contains(id))
    try env.store.delete(id)
    #expect(try env.store.read(id) == nil)
}

@Test func snapshotWrittenThroughSharedIsReadable() throws {
    let (env, _) = try makeTestEnv()
    let id = AccountID(kind: .codex, remoteID: "snap")
    try env.shared.cache.write(UsageSnapshot(accountID: id, fetchedAt: .now, meters: []))
    #expect(env.shared.cache.read(id)?.accountID == id)
}

@Test func directoryProtectionUntilFirstAuth() throws {
    let (env, _) = try makeTestEnv()
    // make() throws if setAttributes fails. The simulator reports no protectionKey (no Data
    // Protection), so accept nil there; a device must report the requested class.
    let attrs = try FileManager.default.attributesOfItem(atPath: env.directory.path)
    let protection = attrs[.protectionKey] as? FileProtectionType
    #expect(protection == nil || protection == .completeUntilFirstUserAuthentication)
}

@Test func liveUsesTheAppGroup() {
    let env = UsageEnvironment.live()
    #expect(env.directory.path.hasPrefix(AppGroup.containerURL.path))
    #expect(env.store.service == "cc.kuoc.agent-hourglass")
}

@Test func makeClientKeepsTheIDForSupportedKinds() async throws {
    var (env, _) = try makeTestEnv()
    env.googleConfigured = true
    for kind in [ProviderKind.claude, .codex, .google, .grok] {
        let id = AccountID(kind: kind, remoteID: "x")
        let client = try #require(env.makeClient(id))
        #expect(await client.id == id)
    }
}

@Test func makeClientBuildsGoogleWhenConfigured() async throws {
    var (env, _) = try makeTestEnv()
    env.googleConfigured = true
    let id = AccountID(kind: .google, remoteID: "g")
    let client = try #require(env.makeClient(id))
    #expect(await client.id == id)
}

@Test func makeClientRejectsGoogleWhenNotConfigured() throws {
    var (env, _) = try makeTestEnv()
    env.googleConfigured = false
    #expect(env.makeClient(AccountID(kind: .google, remoteID: "g")) == nil)
    #expect(env.makeClient(AccountID(kind: .claude, remoteID: "c")) != nil)
}

@Test func makeClientTreatsUnknownKindAsClaude() async throws {
    let (env, _) = try makeTestEnv()
    let id = AccountID(rawValue: "legacy-no-kind")!
    let client = try #require(env.makeClient(id))
    #expect(await client.id == id)
}

@Test func makeClientRejectsCopilotOnIOS() throws {
    let (env, _) = try makeTestEnv()
    #expect(env.makeClient(AccountID(kind: .copilot, remoteID: "x")) == nil)
}
