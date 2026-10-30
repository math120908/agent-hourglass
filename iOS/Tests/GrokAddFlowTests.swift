import Foundation
import Testing
import UsageCore
@testable import AgentHourglass

// Bodies synthesized from R10 §3 (RFC 8628 device flow on auth.x.ai); no live payload exists.

/// Scripted status + body per request, in order.
private final class StatusTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, String)]
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { replies.isEmpty ? (500, "") : replies.removeFirst() }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// Answers by path. The first token poll is held until `release` (ignoring cancellation, like an
/// in-flight POST) and returns tokens; later polls are pending. Records userinfo calls.
private final class RestartTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var polls = 0, userinfos = 0
    private var entered = false, released = false
    let tokens: String
    init(tokens: String) { self.tokens = tokens }
    var firstPollEntered: Bool { lock.withLock { entered } }
    var userinfoCount: Int { lock.withLock { userinfos } }
    func release() { lock.withLock { released = true } }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body): (Int, String)
        switch request.url?.path() {
        case "/oauth2/device/code":
            (status, body) = (200, GrokBodies.start)
        case "/oauth2/token":
            let first = lock.withLock { polls += 1; if polls == 1 { entered = true }; return polls == 1 }
            if first {
                while !lock.withLock({ released }) { try? await Task.sleep(for: .milliseconds(5)) }
                (status, body) = (200, tokens)
            } else {
                (status, body) = (400, GrokBodies.pending)
            }
        default:
            lock.withLock { userinfos += 1 }
            (status, body) = (200, #"{"sub":"user-stale"}"#)
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private enum GrokBodies {
    static let start = #"{"device_code":"DEVICE-SENTINEL","user_code":"ABCD-1234","verification_uri":"https://accounts.x.ai/device","expires_in":900,"interval":5}"#
    static let pending = #"{"error":"authorization_pending"}"#
    static let denied = #"{"error":"access_denied"}"#

    static func tokens(sub: String) -> String {
        let idToken = jwt("{\"sub\":\"\(sub)\",\"email\":\"x@y\"}")
        return "{\"id_token\":\"\(idToken)\",\"access_token\":\"ACCESS-SENTINEL\",\"refresh_token\":\"REFRESH-SENTINEL\",\"expires_in\":3600}"
    }

    private static func b64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func jwt(_ payload: String) -> String { "\(b64url("{\"alg\":\"none\"}")).\(b64url(payload)).sig" }
}

@MainActor struct GrokAddFlowTests {
    private func makeApp() throws -> (UsageEnvironment, AppModel) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let env = try UsageEnvironment.make(base: tmp, service: "cc.kuoc.agent-hourglass.ios-tests", accessGroup: AppGroup.keychainAccessGroup)
        let app = AppModel(env: env, displayStore: DisplaySettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        return (env, app)
    }

    private func settle(_ m: DeviceCodeFlowModel) async throws {
        for _ in 0..<300 {
            switch m.state {
            case .success, .failed, .expired: return
            case .starting, .waiting: try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    @Test func testWiresStartPollAdd() async throws {
        let transport = StatusTransport([
            (200, GrokBodies.start),
            (400, GrokBodies.pending),
            (200, GrokBodies.tokens(sub: "user-synthetic")),
        ])
        let (env, app) = try makeApp()
        let auth = GrokDeviceAuth(http: HTTPClient(transport: transport), sleep: { _ in })
        let m = GrokAddFlow.model(app: app, auth: auth)
        #expect(m.title == "Grok")
        #expect(m.kind == .grok)
        #expect(m.host == "x.ai")
        #expect(m.lead == "Enter this code on x.ai,\nthen come back here.")
        m.begin()
        try await settle(m)
        let expected = AccountID(kind: .grok, remoteID: "user-synthetic")
        #expect(m.state == .success(expected))
        #expect(await env.registry.accounts().contains { $0.id == expected })
        #expect(app.entries.contains { $0.id == expected })
        try? await app.remove(expected)
    }

    @Test func testDeniedShowsItsOwnMessage() async throws {
        let transport = StatusTransport([(200, GrokBodies.start), (400, GrokBodies.denied)])
        let (_, app) = try makeApp()
        let auth = GrokDeviceAuth(http: HTTPClient(transport: transport), sleep: { _ in })
        let m = GrokAddFlow.model(app: app, auth: auth)
        m.begin()
        try await settle(m)
        #expect(m.state == .failed("Sign-in was denied"))
    }

    @Test func testStartFailureShowsTheStatus() async throws {
        let transport = StatusTransport([(503, "")])
        let (_, app) = try makeApp()
        let auth = GrokDeviceAuth(http: HTTPClient(transport: transport), sleep: { _ in })
        let m = GrokAddFlow.model(app: app, auth: auth)
        m.begin()
        try await settle(m)
        #expect(m.state == .failed("The sign-in server answered HTTP 503. Retry"))
    }

    @Test func testRestartDropsTheOldLoginsInFlightCode() async throws {
        let transport = RestartTransport(tokens: GrokBodies.tokens(sub: "user-stale"))
        let (env, app) = try makeApp()
        let auth = GrokDeviceAuth(http: HTTPClient(transport: transport), sleep: { _ in try await Task.sleep(for: .seconds(600)) })
        let m = GrokAddFlow.model(app: app, auth: auth)
        m.begin()
        for _ in 0..<300 where !transport.firstPollEntered { try await Task.sleep(for: .milliseconds(10)) }
        #expect(transport.firstPollEntered)
        m.restart()
        transport.release()
        try await Task.sleep(for: .milliseconds(300))
        let stale = AccountID(kind: .grok, remoteID: "user-stale")
        #expect(!(await env.registry.accounts().contains { $0.id == stale }), "the old login's tokens are never added")
        #expect(transport.userinfoCount == 0)
        if case .waiting = m.state {} else { Issue.record("expected the new login to be waiting, got \(m.state)") }
        m.cancel()
        try? await app.remove(stale)
    }
}
