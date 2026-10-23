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
}
