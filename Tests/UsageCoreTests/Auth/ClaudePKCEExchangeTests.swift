import Foundation
import Testing
@testable import UsageCore

struct ClaudePKCEExchangeTests {
    private let pkce = PKCE.make()

    private func exchange(status: Int, body: String) async throws {
        let http = HTTPClient(transport: RecordingTransport(status: status, body: Data(body.utf8)))
        _ = try await ClaudePKCEFlow.liveExchange(code: "c", pkce: pkce, redirect: ClaudePKCEFlow.manualRedirectURI, http: http)
    }

    /// An expired or already-used authorization code comes back as 400 invalid_grant.
    @Test func expiredCodeIsInvalidGrant() async {
        await #expect(throws: ProviderError.invalidGrant) {
            try await exchange(status: 400, body: #"{"error":"invalid_grant","error_description":"x"}"#)
        }
    }

    @Test func otherFailuresStayHTTP() async {
        await #expect(throws: ProviderError.http(status: 500, host: "platform.claude.com", retryAfter: nil)) {
            try await exchange(status: 500, body: "{}")
        }
    }
}
