import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private final class Codes: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func add(_ c: String) { lock.withLock { seen.append(c) } }
    var all: [String] { lock.withLock { seen } }
}

@MainActor
struct ClaudePasteTests {
    nonisolated private static let cred = Credential(kind: .claude, access: Secret("a"), refresh: Secret("r"), expiresAt: Date().addingTimeInterval(3600), refreshExpiresAt: nil, scopes: ["user:profile"])

    private func model(_ codes: Codes) throws -> (ClaudeSignInModel, String) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let app = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let m = ClaudeSignInModel(app: app, flow: ClaudePKCEFlow { code, _, _ in codes.add(code); return (Self.cred, "acct-uuid") })
        let s = try #require(URLComponents(url: m.authorizeURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value)
        return (m, s)
    }

    @Test func testPasteVariants() async throws {
        let variants: [(String) -> String] = [
            { "abc#\($0)" },
            { "  abc#\($0)\n" },
            { "https://platform.claude.com/oauth/code/callback?code=abc&state=\($0)" },
        ]
        for v in variants {
            let codes = Codes()
            let (m, s) = try model(codes)
            await m.receivePasted(v(s))
            #expect(codes.all == ["abc"])
            #expect(m.state == .success(AccountID(kind: .claude, remoteID: "acct-uuid")))
        }

        let incomplete = Codes()
        let (m1, _) = try model(incomplete)
        await m1.receivePasted("abc")
        #expect(m1.state == .failed("That code isn't complete"))
        #expect(incomplete.all.isEmpty)

        let mismatch = Codes()
        let (m2, _) = try model(mismatch)
        await m2.receivePasted("abc#wrong")
        #expect(m2.state == .failed("Sign-in didn't match. Try again."))
        #expect(mismatch.all.isEmpty)
    }
}
