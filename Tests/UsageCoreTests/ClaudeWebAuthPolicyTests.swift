import XCTest
import UsageCore

final class ClaudeWebAuthPolicyTests: XCTestCase {
    private func d(_ s: String) -> ClaudeWebAuthPolicy.Decision { ClaudeWebAuthPolicy.decide(URL(string: s)!) }

    func testCaptureCallback() {
        XCTAssertEqual(d("https://platform.claude.com/oauth/code/callback?code=abc&state=xyz"), .capture(code: "abc", state: "xyz"))
    }

    func testUnparseableCallbackBlocked() {
        XCTAssertEqual(d("https://platform.claude.com/oauth/code/callback?code=abc"), .block)
        XCTAssertEqual(d("https://platform.claude.com/oauth/code/callback"), .block)
    }

    func testAllowAuthorize() {
        XCTAssertEqual(d("https://claude.com/cai/oauth/authorize?client_id=x&state=y"), .allow)
        XCTAssertEqual(d("https://claude.ai/oauth/authorize"), .allow)
        XCTAssertEqual(d("https://console.anthropic.com/"), .allow)
        XCTAssertEqual(d("https://newassets.hcaptcha.com/captcha"), .allow)
        XCTAssertEqual(d("https://CLAUDE.AI/login"), .allow)
    }

    func testBlockLookalike() {
        XCTAssertEqual(d("https://evilclaude.com/x"), .block)
        XCTAssertEqual(d("http://claude.com/"), .block)
        XCTAssertEqual(d("https://accounts.google.com/"), .block)
        XCTAssertEqual(d("https://claude.com.evil.net/"), .block)
        XCTAssertEqual(d("about:blank"), .block)
    }

    func test_G3_unlistedSubdomainBlocked() {
        XCTAssertEqual(d("https://support.claude.com/"), .block)
        XCTAssertEqual(d("https://docs.anthropic.com/"), .block)
        XCTAssertEqual(d("https://usercontent.claude.ai/x"), .block)
        XCTAssertEqual(d("https://anthropic.com/"), .block)
        XCTAssertEqual(d("https://platform.claude.com/login"), .allow)
        XCTAssertEqual(d("https://www.claude.ai/"), .block)
        XCTAssertEqual(d("https://challenges.cloudflare.com/turnstile"), .allow)
        XCTAssertEqual(d("https://x.challenges.cloudflare.com/"), .allow)
        XCTAssertEqual(d("https://cloudflare.com/"), .block)
    }

    func testConstantTimeEqualPublic() {
        XCTAssertTrue(constantTimeEqual("a", "a"))
        XCTAssertFalse(constantTimeEqual("a", "b"))
    }
}
