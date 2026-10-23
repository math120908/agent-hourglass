import Foundation
import Testing
@testable import UsageCore

struct ClaudeManualCallbackTests {
    private let base = "https://platform.claude.com/oauth/code/callback"

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func parsesCallbackURL() {
        let r = ClaudeManualCallback.parse(url: url("\(base)?code=abc&state=xyz"))
        #expect(r?.code == "abc")
        #expect(r?.state == "xyz")
    }

    @Test func rejectsOtherURLs() {
        let bad = [
            "http://platform.claude.com/oauth/code/callback?code=abc&state=xyz",
            "https://platform.claude.com.evil.com/oauth/code/callback?code=abc&state=xyz",
            "https://claude.ai/oauth/code/callback?code=abc&state=xyz",
            "\(base)/x?code=abc&state=xyz",
            "\(base)?code=abc",
            "\(base)?code=&state=xyz",
            base,
        ]
        for s in bad { #expect(ClaudeManualCallback.parse(url: url(s)) == nil, "\(s)") }
    }

    @Test func rejectsDuplicateParams() {
        #expect(ClaudeManualCallback.parse(url: url("\(base)?code=abc&code=evil&state=xyz")) == nil)
        #expect(ClaudeManualCallback.parse(url: url("\(base)?code=abc&state=xyz&state=evil")) == nil)
    }

    @Test func rejectsPortAndUserinfo() {
        let bad = [
            "https://platform.claude.com:443/oauth/code/callback?code=abc&state=xyz",
            "https://platform.claude.com:8443/oauth/code/callback?code=abc&state=xyz",
            "https://u@platform.claude.com/oauth/code/callback?code=abc&state=xyz",
            "https://u:p@platform.claude.com/oauth/code/callback?code=abc&state=xyz",
        ]
        for s in bad { #expect(ClaudeManualCallback.parse(url: url(s)) == nil, "\(s)") }
    }

    @Test func pastedVariants() {
        for s in ["abc#xyz", "  abc#xyz\n", "\n\tabc#xyz \r\n", "\(base)?code=abc&state=xyz", " \(base)?code=abc&state=xyz\n"] {
            let r = ClaudeManualCallback.parse(pasted: s)
            #expect(r?.code == "abc" && r?.state == "xyz", "\(s)")
        }
        for s in ["abc#", "#xyz", "abc", "", "#", "   ", "a b#xyz", "abc#x y"] {
            #expect(ClaudeManualCallback.parse(pasted: s) == nil, "\(s)")
        }
        let r = ClaudeManualCallback.parse(pasted: "abc#x#y")
        #expect(r?.code == "abc" && r?.state == "x#y")
        #expect(ClaudeManualCallback.parse(pasted: String(repeating: "a", count: 2500) + "#" + String(repeating: "b", count: 2500)) == nil)
        #expect(ClaudeManualCallback.parse(pasted: "https://evil.com/oauth/code/callback?code=abc&state=xyz") == nil)
    }

    @Test func stateMatchesIsExact() {
        #expect(ClaudeManualCallback.stateMatches("s1", expected: "s1"))
        #expect(!ClaudeManualCallback.stateMatches("s1", expected: "s2"))
        #expect(!ClaudeManualCallback.stateMatches("s1x", expected: "s1"))
        #expect(!ClaudeManualCallback.stateMatches("", expected: "s1"))
        // Length differing by 256 must not collide via truncated length XOR.
        #expect(!ClaudeManualCallback.stateMatches(String(repeating: "a", count: 257), expected: "a"))
    }

    @Test func emptyExpectedNeverMatches() {
        #expect(!ClaudeManualCallback.stateMatches("", expected: ""))
        #expect(!ClaudeManualCallback.stateMatches("s1", expected: ""))
    }
}
