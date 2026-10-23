import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

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

    @Test func cancelClosesListener() async throws {
        let listener = try await LoopbackListener.bind()
        let port = listener.port
        let wait = Task { try await listener.awaitCallback(expectedState: "s", timeout: .seconds(30)) }
        try await Task.sleep(for: .milliseconds(100))
        wait.cancel()
        _ = await wait.result
        let again = try await LoopbackListener.bind(maxAttempts: 1, portPicker: { port })
        #expect(again.port == port)
        await again.close()
    }
}
