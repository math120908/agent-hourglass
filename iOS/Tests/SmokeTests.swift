import Foundation
import Testing
@testable import AgentHourglass

@Test func hostBundleIsTheApp() {
    #expect(Bundle.main.bundleIdentifier == "cc.kuoc.agent-hourglass.ios")
}
