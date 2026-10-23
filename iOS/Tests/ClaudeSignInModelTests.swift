import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

@MainActor
struct ClaudeSignInModelTests {
    private func app() throws -> AppModel {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        return AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    nonisolated private static let cred = Credential(kind: .claude, access: Secret("a"), refresh: Secret("r"), expiresAt: Date().addingTimeInterval(3600), refreshExpiresAt: nil, scopes: ["user:profile"])

    @Test func testStateMismatchNeverExchanges() async throws {
        let calls = Counter()
        let m = ClaudeSignInModel(app: try app(), flow: ClaudePKCEFlow { _, _, _ in calls.bump(); return (Self.cred, "x") })
        await m.receive(code: "c", state: "wrong-state")
        #expect(calls.value == 0)
        #expect(m.state == .failed("Sign-in didn't match. Try again."))
    }

    @Test func testHappyPath() async throws {
        let m = ClaudeSignInModel(app: try app(), flow: ClaudePKCEFlow { _, _, _ in (Self.cred, "acct-uuid") })
        let s = try #require(query(m.authorizeURL, "state"))
        await m.receive(code: "c", state: s)
        #expect(m.state == .success(AccountID(kind: .claude, remoteID: "acct-uuid")))
    }

    @Test func testSecondReceiveNeverExchangesAgain() async throws {
        let calls = Counter()
        let m = ClaudeSignInModel(app: try app(), flow: ClaudePKCEFlow { _, _, _ in calls.bump(); return (Self.cred, "acct-uuid") })
        let s = try #require(query(m.authorizeURL, "state"))
        await m.receive(code: "c", state: s)
        await m.receive(code: "c", state: s)
        #expect(calls.value == 1)
    }

    @Test func testRestartChangesState() throws {
        let m = ClaudeSignInModel(app: try app())
        let before = query(m.authorizeURL, "state")
        m.restart()
        #expect(query(m.authorizeURL, "state") != before)
        #expect(m.state == .browsing)
    }

    @Test func testAuthorizeURLUsesManualRedirect() throws {
        let m = ClaudeSignInModel(app: try app())
        #expect(query(m.authorizeURL, "redirect_uri") == ClaudePKCEFlow.manualRedirectURI)
    }
}
