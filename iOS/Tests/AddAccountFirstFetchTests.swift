import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

/// Answers with the queued bodies in order, then `fallback` forever; status 200.
private final class FixedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String]
    private let fallback: String
    init(_ queue: [String] = [], then fallback: String) {
        self.queue = queue
        self.fallback = fallback
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = lock.withLock { queue.isEmpty ? fallback : queue.removeFirst() }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func b64url(_ s: String) -> String {
    Data(s.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func jwt(_ payload: String) -> String { "\(b64url("{\"alg\":\"none\"}")).\(b64url(payload)).sig" }

private let claudeUsage = #"{"five_hour":{"utilization":12,"resets_at":"2030-01-01T05:00:00Z"},"seven_day":{"utilization":40,"resets_at":"2030-01-07T00:00:00Z"}}"#
private let codexUsage = #"{"plan_type":"plus","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":40,"limit_window_seconds":18000,"reset_after_seconds":3600,"reset_at":1800003600},"secondary_window":{"used_percent":55,"limit_window_seconds":604800,"reset_after_seconds":86400,"reset_at":1800086400}}}"#

/// F1: the first usage fetch for a newly added account must land on its card, without a manual refresh.
@MainActor
struct AddAccountFirstFetchTests {
    private func app(usage: String) throws -> AppModel { try appAndEnv(usage: usage).0 }

    private func appAndEnv(usage: String) throws -> (AppModel, UsageEnvironment) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let base = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let env = UsageEnvironment(
            directory: base.directory,
            registry: base.registry,
            store: base.store,
            shared: base.shared,
            http: HTTPClient(transport: FixedTransport(then: usage))
        )
        return (AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)), env)
    }

    private func claudeCred() -> Credential {
        Credential(kind: .claude, access: Secret("a"), refresh: Secret("r"), expiresAt: Date().addingTimeInterval(3600), refreshExpiresAt: nil, scopes: ["user:profile"])
    }

    private func snapshot(_ id: AccountID) -> UsageSnapshot {
        UsageSnapshot(accountID: id, fetchedAt: Date(), meters: [])
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    @Test func testClaudeAddShowsFirstFetchWithoutRefresh() async throws {
        let app = try app(usage: claudeUsage)
        await app.load()
        let cred = Credential(kind: .claude, access: Secret("a"), refresh: Secret("r"), expiresAt: Date().addingTimeInterval(3600), refreshExpiresAt: nil, scopes: ["user:profile"])
        let m = ClaudeSignInModel(app: app, flow: ClaudePKCEFlow { _, _, _ in (cred, "first-fetch") })
        let s = try #require(query(m.authorizeURL, "state"))
        await m.receive(code: "c", state: s)
        let id = AccountID(kind: .claude, remoteID: "first-fetch")
        #expect(m.state == .success(id))
        #expect(app.appState.snapshots[id] != nil)
        #expect(app.appState.statuses[id] == .fresh)
        try? await app.remove(id)
    }

    @Test func testCodexAddShowsFirstFetchWithoutRefresh() async throws {
        let app = try app(usage: codexUsage)
        await app.load()
        let idToken = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"first-fetch"}}"#)
        let accessToken = jwt(#"{"exp":4000000000}"#)
        let auth = CodexDeviceAuth(http: HTTPClient(transport: FixedTransport([
            #"{"device_auth_id":"D","user_code":"ABCD-1234","interval":"5"}"#,
            #"{"authorization_code":"A","code_challenge":"c","code_verifier":"V"}"#,
        ], then: "{\"id_token\":\"\(idToken)\",\"access_token\":\"\(accessToken)\",\"refresh_token\":\"R\"}")), sleep: { _ in })
        let m = CodexAddFlow.model(app: app, auth: auth)
        m.begin()
        for _ in 0..<300 {
            if case .success = m.state { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let id = AccountID(kind: .codex, remoteID: "first-fetch")
        #expect(m.state == .success(id))
        #expect(app.appState.snapshots[id] != nil)
        #expect(app.appState.statuses[id] == .fresh)
        try? await app.remove(id)
    }

    /// A direct result for an id that became known mid-add is newer than the one held for it;
    /// the held one must not be replayed over it when the outer add ends.
    @Test func testHeldResultDoesNotOverwriteNewerDirectDelivery() async throws {
        let app = try app(usage: claudeUsage)
        await app.load()
        let id = AccountID(kind: .claude, remoteID: "held-vs-direct")
        _ = try await app.add {
            _ = try await app.add {
                let added = try await app.service.addClaude(credential: claudeCred(), remoteID: "held-vs-direct")
                app.deliver(added, .failure(.needsLogin))
                return added
            }
            app.deliver(id, .success(snapshot(id)))
            return id
        }
        #expect(app.appState.statuses[id] == .fresh)
        try? await app.remove(id)
    }

    /// A result for an id still unknown when the add ends (removed mid-add) is dropped on replay.
    @Test func testUnknownResultHeldDuringAddIsDroppedAfterReplay() async throws {
        let (app, env) = try appAndEnv(usage: claudeUsage)
        await app.load()
        let gone = AccountID(kind: .claude, remoteID: "removed-mid-add")
        try env.shared.cache.write(snapshot(gone))
        let id = try await app.add {
            let added = try await app.service.addClaude(credential: claudeCred(), remoteID: "mid-add")
            app.deliver(gone, .success(snapshot(gone)))
            return added
        }
        #expect(app.appState.snapshots[gone] == nil)
        #expect(app.appState.statuses[gone] == nil)
        #expect(!app.appState.accounts.contains(gone))
        #expect(env.shared.cache.read(gone) == nil)
        try? await app.remove(id)
    }
}
