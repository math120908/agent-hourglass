import Foundation
import Observation
import UsageCore

/// SPIKE, dev builds only: Google loopback PKCE sign-in, shown in the ephemeral `PasteBrowser`.
/// Google redirects to the `127.0.0.1` listener inside the sheet; once the code is exchanged the
/// sheet is dismissed with `browser.cancel()`. Closing the sheet before that ends the flow.
@MainActor @Observable final class GoogleSignInModel {
    enum State: Equatable { case idle, waiting, success(AccountID), failed(String) }

    private(set) var state: State = .idle

    @ObservationIgnored private let app: AppModel?
    @ObservationIgnored private let signIn: GoogleSignIn
    @ObservationIgnored private let browser: PasteBrowser
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel, signIn: GoogleSignIn, browser: PasteBrowser = PasteBrowser()) {
        self.app = app
        self.signIn = signIn
        self.browser = browser
    }

    /// The live flow: the bundle's dev-only client secret, tokens over the app's HTTP client.
    convenience init(app: AppModel) {
        self.init(app: app, signIn: GoogleSignIn(oauth: GoogleOAuth(http: app.http), client: BundleGoogleOAuthClient()))
    }

    /// Fixed-state init for previews and snapshots; never signs in.
    init(state: State) {
        app = nil
        signIn = GoogleSignIn(oauth: GoogleOAuth(http: HTTPClient()), client: BundleGoogleOAuthClient())
        browser = PasteBrowser()
        self.state = state
    }

    func start() {
        cancel()
        state = .waiting
        task = Task { await run() }
    }

    /// The add sheet went away: stop listening and tear the auth sheet down.
    func cancel() {
        task?.cancel()
        task = nil
        browser.cancel()
    }

    private func run() async {
        do {
            // `run` awaits `open` before it listens, so `open` only presents the sheet and returns.
            let credential = try await signIn.run(open: { [weak self] url in await self?.present(url) })
            guard !Task.isCancelled else { return }
            browser.cancel()
            guard let app else { return }
            let service = app.service
            let id = try await app.add { try await service.addGoogle(credential: credential) }
            state = .success(id)
        } catch {
            guard !Task.isCancelled else { return }
            browser.cancel()
            state = Self.failure(error)
        }
    }

    private func present(_ url: URL) {
        guard !Task.isCancelled, state == .waiting else { return }
        browser.open(url) { [weak self] in self?.browserClosed() }
    }

    /// The user closed the sheet before the listener got a code.
    private func browserClosed() {
        guard state == .waiting else { return }
        task?.cancel()
        task = nil
        state = .failed("Sign-in was cancelled")
    }

    private static func failure(_ error: any Error) -> State {
        if case GoogleOAuthError.clientUnavailable = error { return .failed("Google sign-in is not configured in this build") }
        guard case let .failed(message) = AddFlowState.googleFailure(error) else { return .failed("Sign-in failed") }
        return .failed(message)
    }
}
