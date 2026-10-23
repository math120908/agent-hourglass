import Foundation
import Observation
import UsageCore

/// Drives the Claude authorization-code + PKCE sign-in for the in-app web view and the paste flow.
/// The verifier, code and state are never logged or shown.
@MainActor @Observable final class ClaudeSignInModel {
    enum State: Equatable {
        case browsing
        case exchanging
        case success(AccountID)
        case failed(String)
    }

    private(set) var authorizeURL: URL
    private(set) var state: State = .browsing

    @ObservationIgnored private let app: AppModel?
    @ObservationIgnored private let flow: ClaudePKCEFlow
    @ObservationIgnored private let loginHint: String?
    /// Single-use: cleared after one state comparison, whether it matched or not.
    @ObservationIgnored private var pkce: PKCE?

    init(app: AppModel, flow: ClaudePKCEFlow = ClaudePKCEFlow(), loginHint: String? = nil) {
        self.app = app
        self.flow = flow
        self.loginHint = loginHint
        let p = PKCE.make()
        pkce = p
        authorizeURL = flow.authorizeURL(pkce: p, redirectURI: ClaudePKCEFlow.manualRedirectURI, loginHint: loginHint)
    }

    /// Fixed-state init for previews and snapshots; never exchanges.
    init(state: State) {
        app = nil
        flow = ClaudePKCEFlow { _, _, _ in throw CancellationError() }
        loginHint = nil
        pkce = nil
        authorizeURL = URL(string: "https://claude.ai")!
        self.state = state
    }

    func receive(code: String, state received: String) async {
        guard state == .browsing else { return }
        let expected = pkce
        pkce = nil
        guard let expected, let app,
              ClaudeManualCallback.stateMatches(received, expected: expected.state)
        else {
            state = .failed("Sign-in didn't match. Try again.")
            return
        }
        state = .exchanging
        do {
            let (cred, remoteID) = try await flow.exchange(code: code, pkce: expected, redirectURI: ClaudePKCEFlow.manualRedirectURI)
            let id = try await app.service.addClaude(credential: cred, remoteID: remoteID)
            await app.accountAdded(id)
            state = .success(id)
        } catch AccountServiceError.differentAccount {
            state = .failed("That was a different account")
        } catch {
            state = .failed("Sign-in failed")
        }
    }

    func restart() {
        let p = PKCE.make()
        pkce = p
        authorizeURL = flow.authorizeURL(pkce: p, redirectURI: ClaudePKCEFlow.manualRedirectURI, loginHint: loginHint)
        state = .browsing
    }
}
