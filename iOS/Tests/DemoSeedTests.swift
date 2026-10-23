import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

@Test func seedThenClear() async throws {
    let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
    try await DemoSeed.seed(env)
    var lines = await ShellStatus.load(env, now: .now)
    #expect(lines.map(\.text) == ["Demo | claude | 0s ago | key yes"])
    try await DemoSeed.clear(env)
    lines = await ShellStatus.load(env, now: .now)
    #expect(lines.isEmpty)
    #expect(try env.store.allAccountIDs().contains(AccountID(kind: .claude, remoteID: DemoSeed.remoteID)) == false)
}

@Test func clearWhenNothingSeededIsQuiet() async throws {
    let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
    try await DemoSeed.clear(env)
}
