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

    @Test func deviceExpiredMessage() {
        #expect(AddFlowState.deviceFailure(DeviceFlowError.expired) == .failed("The code expired. Retry for a new one"))
    }

    @Test func deviceDeniedMessage() {
        #expect(AddFlowState.deviceFailure(DeviceFlowError.denied) == .failed("Sign-in was denied"))
    }

    /// The userinfo call after a granted code throws `ProviderError`; each case gets its own message.
    @Test func deviceProviderErrorMessages() {
        #expect(AddFlowState.deviceFailure(DeviceFlowError.unexpected(status: 500)) == .failed("The sign-in server answered HTTP 500. Retry"))
        #expect(AddFlowState.deviceFailure(ProviderError.http(status: 502, host: "auth.x.ai", retryAfter: nil)) == .failed("The sign-in server answered HTTP 502. Retry"))
        #expect(AddFlowState.deviceFailure(ProviderError.unauthorized) == .failed("The new sign-in was rejected. Retry"))
        #expect(AddFlowState.deviceFailure(ProviderError.invalidGrant) == .failed("The new sign-in was rejected. Retry"))
        #expect(AddFlowState.deviceFailure(ProviderError.schema(keys: ["x"])) == .failed("Unexpected answer from the sign-in server"))
        #expect(AddFlowState.deviceFailure(ProviderError.transport(host: "auth.x.ai")) == .failed("Network error during sign-in. Check the connection and retry"))
        #expect(AddFlowState.deviceFailure(ProviderError.rateLimited(retryAfter: nil)) == .failed("Too many sign-in attempts. Wait a minute and retry"))
        #expect(AddFlowState.deviceFailure(AccountServiceError.missingAccountID) == .failed("The sign-in did not identify an account"))
    }

    @Test func deviceFailureFallsBackToFailure() {
        #expect(AddFlowState.deviceFailure(AccountServiceError.signInInProgress) == .failed("Sign-in already in progress"))
        #expect(AddFlowState.deviceFailure(CancellationError()) == .failed("Sign-in failed"))
    }
}

