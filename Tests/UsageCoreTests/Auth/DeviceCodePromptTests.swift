import Foundation
import Testing
@testable import UsageCore

struct DeviceCodePromptTests {
    private let deviceCode = "dev-code-SENTINEL-1234"

    private func prompt() -> DeviceCodePrompt {
        DeviceCodePrompt(
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://auth.example.com/device")!,
            interval: .seconds(5),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            deviceCode: Secret(deviceCode)
        )
    }

    @Test func descriptionHidesDeviceCode() {
        let p = prompt()
        var dumped = ""
        dump(p, to: &dumped)
        for s in ["\(p)", String(reflecting: p), String(describing: Mirror(reflecting: p).children.map { $0.value }), dumped] {
            #expect(!s.contains(deviceCode))
        }
        #expect("\(p)".contains("ABCD-EFGH"))
        #expect("\(p)".contains("auth.example.com"))
    }

    @Test func scriptedTransportReplaysInOrderAndRecords() async throws {
        let t = ScriptedTransport([
            (status: 200, body: #"{"ok":true}"#, headers: [:]),
            (status: 428, body: "{}", headers: ["Retry-After": "5"]),
        ])
        var r1 = URLRequest(url: URL(string: "https://example.com/a")!)
        r1.httpMethod = "POST"
        r1.httpBody = Data(#"{"client_id":"x"}"#.utf8)
        var r2 = URLRequest(url: URL(string: "https://example.com/b")!)
        r2.httpMethod = "POST"
        r2.httpBody = Data("grant_type=device&code=a%20b".utf8)
        let (_, resp1) = try await t.data(for: r1)
        let (_, resp2) = try await t.data(for: r2)
        #expect(resp1.statusCode == 200)
        #expect(resp2.statusCode == 428)
        #expect(resp2.value(forHTTPHeaderField: "Retry-After") == "5")
        #expect(t.requests.count == 2)
        #expect(t.bodyJSON(0)?["client_id"] as? String == "x")
        #expect(t.bodyForm(1) == ["grant_type": "device", "code": "a b"])
    }
}
