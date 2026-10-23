import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private func tempCache() -> (SnapshotCache, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return (SnapshotCache(directory: dir), dir)
}

private func entry(_ name: String, _ kind: ProviderKind, order: Int) -> AccountEntry {
    AccountEntry(id: AccountID(kind: kind, remoteID: name), kind: kind, displayName: name, remoteLogin: nil, order: order, addedAt: .now, status: "ok")
}

@Test func lineText() throws {
    let (c, _) = tempCache()
    let now = Date()
    let e = entry("Work", .claude, order: 0)
    try c.write(UsageSnapshot(accountID: e.id, fetchedAt: now.addingTimeInterval(-180), meters: []))
    let lines = ShellStatus.lines(entries: [e], cache: c, credentialIDs: [e.id], now: now)
    #expect(lines.first?.text == "Work | claude | 3m ago | key yes")
    #expect(lines.first?.snapshotAge == 180)
}

@Test func ageBuckets() throws {
    let (c, _) = tempCache()
    let now = Date()
    let e = entry("A", .claude, order: 0)
    for (age, want) in [(5.0, "5s ago"), (59.9, "59s ago"), (3599, "59m ago"), (7200, "2h ago")] {
        try c.write(UsageSnapshot(accountID: e.id, fetchedAt: now.addingTimeInterval(-age), meters: []))
        #expect(ShellStatus.lines(entries: [e], cache: c, credentialIDs: [], now: now).first?.text == "A | claude | \(want) | key no")
    }
}

@Test func noSnapshotNoKey() {
    let (c, _) = tempCache()
    let lines = ShellStatus.lines(entries: [entry("Home", .codex, order: 0)], cache: c, credentialIDs: [], now: .now)
    #expect(lines.first?.text == "Home | codex | no snapshot | key no")
}

@Test func garbageSnapshotShowsNoSnapshot() throws {
    let (c, dir) = tempCache()
    let e = entry("Work", .claude, order: 0)
    try c.write(UsageSnapshot(accountID: e.id, fetchedAt: .now, meters: []))
    let snaps = dir.appending(path: "snapshots")
    let files = try FileManager.default.contentsOfDirectory(atPath: snaps.path)
    #expect(files.count == 1)
    try Data("{".utf8).write(to: snaps.appending(path: files[0]))
    let lines = ShellStatus.lines(entries: [e], cache: c, credentialIDs: [], now: .now)
    #expect(lines.count == 1)
    #expect(lines.first?.snapshotAge == nil)
}

@Test func orderFollowsRegistryOrder() {
    let (c, _) = tempCache()
    let lines = ShellStatus.lines(entries: [entry("B", .codex, order: 1), entry("A", .claude, order: 0)], cache: c, credentialIDs: [], now: .now)
    #expect(lines.map(\.name) == ["A", "B"])
}

@Test func emptyRegistry() {
    let (c, _) = tempCache()
    #expect(ShellStatus.lines(entries: [], cache: c, credentialIDs: [], now: .now).isEmpty)
}

@Test func loadOnEmptyEnvironment() async throws {
    let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
    #expect(await ShellStatus.load(env, now: .now).isEmpty)
}
