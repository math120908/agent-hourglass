import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

struct AddFlowTests {
    private func entry(_ kind: ProviderKind, login: String?) -> AccountEntry {
        AccountEntry(id: AccountID(kind: kind, remoteID: "r"), kind: kind, displayName: "d", remoteLogin: login, order: 0, addedAt: Date(timeIntervalSince1970: 0), status: "ok")
    }

    @Test func testClaudeSignInPassesLoginHint() {
        #expect(AddFlow.signIn(for: entry(.claude, login: "a@b")) == .claude(loginHint: "a@b"))
    }

    @Test func testCodexSignIn() {
        #expect(AddFlow.signIn(for: entry(.codex, login: nil)) == .codex)
    }

    @Test func testCopilotHasNoFlow() {
        #expect(AddFlow.signIn(for: entry(.copilot, login: "x")) == nil)
    }

    @Test func testIdsDistinct() {
        #expect(AddFlow.codex.id != AddFlow.claude(loginHint: nil).id)
    }

    @Test func testGoogleIdAndKind() {
        #expect(AddFlow.google.id == "google")
        #expect(AddFlow.google.kind == .google)
    }

    @Test func testGoogleSignInOnlyWhenConfigured() {
        #expect(AddFlow.signIn(for: entry(.google, login: "a@b"), googleConfigured: false) == nil)
        #expect(AddFlow.signIn(for: entry(.google, login: "a@b"), googleConfigured: true) == .google)
    }

    /// The test host has no xcconfig, so the default build offers no Google flow.
    @Test func testGoogleAbsentByDefault() {
        #expect(!BundleGoogleOAuthClient.isConfigured())
        #expect(AddFlow.signIn(for: entry(.google, login: nil)) == nil)
    }
}
