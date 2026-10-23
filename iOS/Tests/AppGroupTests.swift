import Foundation
import Testing
@testable import AgentHourglass

@Test func groupID() { #expect(AppGroup.id == "group.cc.kuoc.agent-hourglass") }

@Test func keychainGroupExpandedFromInfoPlist() {
    #expect(AppGroup.keychainAccessGroup == "R7V5X99HYA.cc.kuoc.agent-hourglass.shared")
}

@Test func containerIsTheSharedGroupContainer() {
    #expect(AppGroup.containerURL.path.contains("/Shared/AppGroup/"))
    #expect(FileManager.default.fileExists(atPath: AppGroup.containerURL.path))
}

@Test func defaultsRoundTripAcrossInstances() {
    let key = "apptest.\(UUID().uuidString)"
    AppGroup.defaults.set("x", forKey: key)
    #expect(UserDefaults(suiteName: AppGroup.id)?.string(forKey: key) == "x")
    AppGroup.defaults.removeObject(forKey: key)
}
