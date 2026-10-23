import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct DeepLinkTests {
    @Test func testRoundTrip() {
        let id = AccountID.claudeCodeLocal
        let url = DeepLink.url(for: id)
        #expect(url.scheme == "agenthourglass")
        #expect(url.host == "account")
        #expect(DeepLink.accountID(from: url) == id)
    }

    @Test func testReservedCharactersRoundTrip() {
        let id = AccountID(rawValue: "copilot:a&b=c?d/e#f+g h%20")!
        let url = DeepLink.url(for: id)
        #expect(!url.absoluteString.contains("#"))
        #expect(!url.absoluteString.contains(" "))
        #expect(DeepLink.accountID(from: url) == id)
    }

    @Test func testRejectsWrongScheme() {
        #expect(DeepLink.accountID(from: URL(string: "https://account?id=claude:x")!) == nil)
    }

    @Test func testRejectsWrongHost() {
        #expect(DeepLink.accountID(from: URL(string: "agenthourglass://settings?id=claude:x")!) == nil)
    }

    @Test func testRejectsMissingID() {
        #expect(DeepLink.accountID(from: URL(string: "agenthourglass://account")!) == nil)
        #expect(DeepLink.accountID(from: URL(string: "agenthourglass://account?other=1")!) == nil)
        #expect(DeepLink.accountID(from: URL(string: "agenthourglass://account?id=")!) == nil)
    }
}
