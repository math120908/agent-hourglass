import AuthenticationServices
import UIKit

/// Holds the ephemeral ASWebAuthenticationSession for the Claude paste flow. The callback URL is
/// never reached: the user copies the code and closes the sheet. `onReturn` fires once per open,
/// whatever the result (closing the sheet is the normal way back).
@MainActor final class PasteBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    /// Bumped per open, so cancelling a previous session does not report a return.
    private var generation = 0

    func open(_ url: URL, onReturn: @escaping @MainActor () -> Void) {
        generation += 1
        let current = generation
        session?.cancel()
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "agenthourglass") { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.session = nil
                onReturn()
            }
        }
        s.prefersEphemeralWebBrowserSession = true
        s.presentationContextProvider = self
        session = s
        s.start()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
