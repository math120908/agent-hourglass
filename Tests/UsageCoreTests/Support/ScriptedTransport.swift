import Foundation
import Testing
@testable import UsageCore

/// Replays queued responses in order and records every request. When the queue is
/// exhausted it records a test issue and returns status 599.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(status: Int, body: String, headers: [String: String])]
    private var recorded: [URLRequest] = []

    init(_ responses: [(status: Int, body: String, headers: [String: String])]) {
        self.responses = responses
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: (status: Int, body: String, headers: [String: String])? = lock.withLock {
            recorded.append(request)
            return responses.isEmpty ? nil : responses.removeFirst()
        }
        guard let next else {
            Issue.record("ScriptedTransport exhausted: \(request.url?.absoluteString ?? "?")")
            return (Data(), Self.response(request, 599, [:]))
        }
        return (Data(next.body.utf8), Self.response(request, next.status, next.headers))
    }

    func bodyJSON(_ i: Int) -> [String: Any]? {
        guard let body = requests[i].httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    func bodyForm(_ i: Int) -> [String: String] {
        guard let body = requests[i].httpBody, let s = String(data: body, encoding: .utf8) else { return [:] }
        var c = URLComponents()
        c.percentEncodedQuery = s.replacingOccurrences(of: "+", with: "%20")
        var out: [String: String] = [:]
        for item in c.queryItems ?? [] { out[item.name] = item.value ?? "" }
        return out
    }

    private static func response(_ request: URLRequest, _ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "about:blank")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
