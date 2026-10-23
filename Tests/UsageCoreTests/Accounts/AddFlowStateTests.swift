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
}
