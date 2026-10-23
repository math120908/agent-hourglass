import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String]
    init(_ bodies: [String]) { self.bodies = bodies }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = lock.withLock { bodies.isEmpty ? "" : bodies.removeFirst() }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Answers by path. The first token poll is held until `release` (ignoring cancellation, like an
/// in-flight POST) and returns a code; later polls are pending. Records exchange calls.
private final class RestartTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var polls = 0, exchanges = 0
    private var entered = false, released = false
    let tokens: String
    init(tokens: String) { self.tokens = tokens }
    var firstPollEntered: Bool { lock.withLock { entered } }
    var exchangeCount: Int { lock.withLock { exchanges } }
    func release() { lock.withLock { released = true } }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body): (Int, String)
        switch request.url?.path() {
        case "/api/accounts/deviceauth/usercode":
            (status, body) = (200, #"{"device_auth_id":"DAID-SENTINEL","user_code":"ABCD-1234","interval":"5"}"#)
        case "/api/accounts/deviceauth/token":
            let first = lock.withLock { polls += 1; if polls == 1 { entered = true }; return polls == 1 }
            if first {
                while !lock.withLock({ released }) { try? await Task.sleep(for: .milliseconds(5)) }
                (status, body) = (200, #"{"authorization_code":"AUTHCODE-SENTINEL","code_challenge":"c","code_verifier":"VERIFIER-SENTINEL"}"#)
            } else {
                (status, body) = (403, "")
            }
        default:
            lock.withLock { exchanges += 1 }
            (status, body) = (200, tokens)
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// Scripted status + body per request; counts token polls.
private final class StatusTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, String)]
    private var tokenPolls = 0
    init(_ replies: [(Int, String)]) { self.replies = replies }
    var polls: Int { lock.withLock { tokenPolls } }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock {
            if request.url?.path() == "/api/accounts/deviceauth/token" { tokenPolls += 1 }
            return replies.isEmpty ? (500, "") : replies.removeFirst()
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.withLock { v } } set { lock.withLock { v = newValue } } }
}

private func b64url(_ s: String) -> String {
    Data(s.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func jwt(_ payload: String) -> String { "\(b64url("{\"alg\":\"none\"}")).\(b64url(payload)).sig" }

@MainActor struct CodexAddFlowTests {
    @Test func testWiresStartPollAdd() async throws {
        let idToken = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-synthetic"},"email":"x@y"}"#)
        let accessToken = jwt(#"{"exp":4000000000}"#)
        let transport = StubTransport([
            #"{"device_auth_id":"DAID-SENTINEL","user_code":"ABCD-1234","interval":"5"}"#,
            #"{"authorization_code":"AUTHCODE-SENTINEL","code_challenge":"c","code_verifier":"VERIFIER-SENTINEL"}"#,
            "{\"id_token\":\"\(idToken)\",\"access_token\":\"\(accessToken)\",\"refresh_token\":\"REFRESH-SENTINEL\"}",
        ])
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let app = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let auth = CodexDeviceAuth(http: HTTPClient(transport: transport), sleep: { _ in })
        let m = CodexAddFlow.model(app: app, auth: auth)
        #expect(m.title == "Codex")
        m.begin()
        for _ in 0..<300 {
            if case .success = m.state { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let expected = AccountID(kind: .codex, remoteID: "acct-synthetic")
        #expect(m.state == .success(expected))
        #expect(expected.kind == .codex)
        #expect(await env.registry.accounts().contains { $0.id == expected })
        #expect(app.entries.contains { $0.id == expected })
        try? await app.remove(expected)
    }

    @Test func testForegroundPollsAtOnceOnceIntervalElapsed() async throws {
        let idToken = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-wake"}}"#)
        let accessToken = jwt(#"{"exp":4000000000}"#)
        let transport = StatusTransport([
            (200, #"{"device_auth_id":"DAID-SENTINEL","user_code":"ABCD-1234","interval":"5"}"#),
            (403, ""),
            (200, #"{"authorization_code":"AUTHCODE-SENTINEL","code_challenge":"c","code_verifier":"VERIFIER-SENTINEL"}"#),
            (200, "{\"id_token\":\"\(idToken)\",\"access_token\":\"\(accessToken)\",\"refresh_token\":\"REFRESH-SENTINEL\"}"),
        ])
        let m0 = ContinuousClock.now
        let mono = Box(m0)
        let sleeps = Box(0)
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let app = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        // The interval timer never fires on its own: only the foreground wake can move the poll on.
        let auth = CodexDeviceAuth(
            http: HTTPClient(transport: transport),
            sleep: { _ in sleeps.value += 1; try await Task.sleep(for: .seconds(600)) },
            monotonic: { mono.value },
        )
        let m = CodexAddFlow.model(app: app, auth: auth)
        m.begin()
        for _ in 0..<300 where sleeps.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(transport.polls == 1)
        m.foreground()
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.polls == 1, "back within the interval: no early poll")
        mono.value = m0 + .seconds(6)
        m.foreground()
        for _ in 0..<300 {
            if case .success = m.state { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let expected = AccountID(kind: .codex, remoteID: "acct-wake")
        #expect(m.state == .success(expected))
        #expect(transport.polls == 2)
        try? await app.remove(expected)
    }

    @Test func testRestartDropsTheOldLoginsInFlightCode() async throws {
        let idToken = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-stale"}}"#)
        let accessToken = jwt(#"{"exp":4000000000}"#)
        let transport = RestartTransport(tokens: "{\"id_token\":\"\(idToken)\",\"access_token\":\"\(accessToken)\",\"refresh_token\":\"REFRESH-SENTINEL\"}")
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let app = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let auth = CodexDeviceAuth(http: HTTPClient(transport: transport), sleep: { _ in try await Task.sleep(for: .seconds(600)) })
        let m = CodexAddFlow.model(app: app, auth: auth)
        m.begin()
        for _ in 0..<300 where !transport.firstPollEntered { try await Task.sleep(for: .milliseconds(10)) }
        #expect(transport.firstPollEntered)
        m.restart()
        transport.release()
        try await Task.sleep(for: .milliseconds(300))
        let stale = AccountID(kind: .codex, remoteID: "acct-stale")
        #expect(transport.exchangeCount == 0, "the old login's code is never exchanged")
        #expect(!(await env.registry.accounts().contains { $0.id == stale }))
        if case .waiting = m.state {} else { Issue.record("expected the new login to be waiting, got \(m.state)") }
        m.cancel()
        try? await app.remove(stale)
    }
}
