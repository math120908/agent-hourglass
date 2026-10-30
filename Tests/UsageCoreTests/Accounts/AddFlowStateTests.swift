import Foundation
import Testing
@testable import UsageCore

struct AddFlowStateTests {
    @Test func concurrentAddRejected() {
        var state = AddFlowState.idle
        let first = state.begin()
        let second = state.begin()
        #expect(first)
        #expect(!second)
        #expect(AddFlowState.failure(AccountServiceError.signInInProgress) == .failed("Sign-in already in progress"))
        state = .failed("x")
        let retry = state.begin()
        #expect(retry)
    }

    @Test func differentAccountMessage() {
        #expect(AddFlowState.failure(AccountServiceError.differentAccount) == .failed("Signed in as a different account"))
        #expect(AddFlowState.failure(AuthError.differentAccount) == .failed("Signed in as a different account"))
    }

    @Test func googleClientUnavailableMessage() {
        #expect(AddFlowState.googleFailure(GoogleOAuthError.clientUnavailable) == .failed("Install Antigravity or the agy CLI first"))
        #expect(AddFlowState.googleFailure(AuthError.timeout) == AddFlowState.failure(AuthError.timeout))
    }

    @Test func googleProviderErrorsHaveSpecificMessages() {
        let errors: [any Error] = [
            GoogleOAuthError.clientRejected,
            ProviderError.invalidGrant,
            ProviderError.unauthorized,
            ProviderError.http(status: 500, host: "oauth2.googleapis.com", retryAfter: nil),
            ProviderError.rateLimited(retryAfter: nil),
            ProviderError.schema(keys: ["sub"]),
            ProviderError.transport(host: "oauth2.googleapis.com"),
            ProviderError.hostNotAllowed("example.com"),
            ProviderError.redirectRefused(host: "oauth2.googleapis.com"),
            AccountServiceError.missingAccountID,
        ]
        for error in errors {
            #expect(AddFlowState.googleFailure(error) != .failed("Sign-in failed"), "\(error)")
        }
        #expect(AddFlowState.googleFailure(ProviderError.http(status: 503, host: "oauth2.googleapis.com", retryAfter: nil)) == .failed("Google answered HTTP 503. Retry"))
    }
}
