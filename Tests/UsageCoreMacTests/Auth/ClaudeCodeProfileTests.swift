import Foundation
import Testing
@testable import UsageCoreMac

struct ClaudeCodeProfileTests {
    func file(_ account: [String: Any]?) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString).json")
        let root: [String: Any] = account.map { ["oauthAccount": $0] } ?? [:]
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        return url
    }

    @Test func precedence() throws {
        let all = ["displayName": "CK", "fullName": "Chris Kuo", "emailAddress": "c@x.com"]
        #expect(ClaudeCodeProfile.userName(at: try file(all)) == "CK")
        #expect(ClaudeCodeProfile.userName(at: try file(["displayName": " ", "fullName": "Chris Kuo", "emailAddress": "c@x.com"])) == "Chris Kuo")
        #expect(ClaudeCodeProfile.userName(at: try file(["emailAddress": "c@x.com"])) == "c@x.com")
    }

    @Test func missingFileOrFieldsIsNil() throws {
        #expect(ClaudeCodeProfile.userName(at: URL(fileURLWithPath: "/nonexistent/.claude.json")) == nil)
        #expect(ClaudeCodeProfile.userName(at: try file(nil)) == nil)
        #expect(ClaudeCodeProfile.userName(at: try file(["organizationName": "Org"])) == nil)
    }
}
