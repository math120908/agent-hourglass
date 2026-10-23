import AuthenticationServices
import UIKit

/// The auth session PasteBrowser drives. ASWebAuthenticationSession in the app, a fake in tests.
protocol PasteAuthSession: AnyObject {
    @discardableResult func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: PasteAuthSession {}

/// Holds the ephemeral ASWebAuthenticationSession for the Claude paste flow. The callback URL is
/// never reached: the user copies the code and closes the sheet. `onReturn` fires once per open,
/// whatever the result (closing the sheet is the normal way back), unless `cancel()` ran first.
@MainActor final class PasteBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    typealias MakeSession = @MainActor (URL, PasteBrowser, @escaping @Sendable () -> Void) -> any PasteAuthSession

    private let makeSession: MakeSession
    private var session: (any PasteAuthSession)?
    /// Bumped per open and per cancel, so an ended or replaced session does not report a return.
    private var generation = 0

    var isActive: Bool { session != nil }

    init(makeSession: @escaping MakeSession = PasteBrowser.ephemeralSession) {
        self.makeSession = makeSession
        super.init()
    }

    func open(_ url: URL, onReturn: @escaping @MainActor () -> Void) {
        generation += 1
        let current = generation
        session?.cancel()
        let s = makeSession(url, self) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.session = nil
                onReturn()
            }
        }
        session = s
        s.start()
    }

    /// Tears the session down when the sheet goes away; its completion no longer reports a return.
    func cancel() {
        generation += 1
        session?.cancel()
        session = nil
    }

    static func ephemeralSession(_ url: URL, _ provider: PasteBrowser, _ done: @escaping @Sendable () -> Void) -> any PasteAuthSession {
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "agenthourglass") { _, _ in done() }
        s.prefersEphemeralWebBrowserSession = true
        s.presentationContextProvider = provider
        return s
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.lazy.compactMap(\.keyWindow).first ?? scenes.lazy.flatMap(\.windows).first {
                return window
            }
            guard let scene = scenes.first else { preconditionFailure("no window scene to present the auth sheet") }
            return ASPresentationAnchor(windowScene: scene)
        }
    }
}
