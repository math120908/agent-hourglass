import Foundation
import Testing
@testable import UsageCore

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]

    static func reset(status: Int = 200, headers: [String: String] = [:]) {
        requests = []
        self.status = status
        self.headers = headers
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct HTTPClientTests {
    let client = HTTPClient(extraProtocolClasses: [StubProtocol.self])
    let bearer = Secret("tok-AAAA1234")

    @Test func bearerToForeignHostRejected() async {
        StubProtocol.reset()
        let req = URLRequest(url: URL(string: "https://example.com/x")!)
        await #expect(throws: ProviderError.hostNotAllowed("example.com")) {
            _ = try await client.send(req, bearer: bearer)
        }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func redirectRefusedOnAuthenticated() async {
        StubProtocol.reset(status: 302, headers: ["Location": "https://example.com/steal"])
        let req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        await #expect(throws: ProviderError.redirectRefused(host: "api.anthropic.com")) {
            _ = try await client.send(req, bearer: bearer)
        }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func noCookiesNoCache() {
        #expect(client.configuration.httpCookieStorage == nil)
        #expect(client.configuration.urlCache == nil)
    }

    @Test func retryAfterParsed() async {
        StubProtocol.reset(status: 429, headers: ["Retry-After": "120"])
        let req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        await #expect(throws: ProviderError.rateLimited(retryAfter: .seconds(120))) {
            _ = try await client.send(req, bearer: bearer)
        }
    }

    @Test func bearerAttachedOnAllowedHost() async throws {
        StubProtocol.reset()
        let req = URLRequest(url: URL(string: "https://api.github.com/user")!)
        let (_, resp) = try await client.send(req, bearer: bearer)
        #expect(resp.statusCode == 200)
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-AAAA1234")
    }

    @Test func errorDescriptionHasNoQuery() async {
        StubProtocol.reset(status: 500)
        let req = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token?code=SECRET")!)
        do {
            _ = try await client.send(req, bearer: nil)
            Issue.record("expected throw")
        } catch {
            #expect(!String(describing: error).contains("SECRET"))
            #expect(!error.localizedDescription.contains("SECRET"))
        }
    }
}
