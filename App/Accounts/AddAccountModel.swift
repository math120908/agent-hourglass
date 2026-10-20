import AppKit
import Observation
import UsageCore

/// Drives the Add Account sheet. One flow at a time across all windows.
@MainActor @Observable
final class AddAccountModel {
    enum Step { case provider, claudeEmail, flow }

    /// The authorize URL of the flow in progress (never the verifier), for "Copy link".
    static var currentURL: URL?

    var step: Step = .provider
    var email = ""
    var state = AddFlowState.idle
    private let engine: UsageEngine
    private var task: Task<Void, Never>?

    init(engine: UsageEngine) { self.engine = engine }

    static func open(_ url: URL) {
        currentURL = url
        NSWorkspace.shared.open(url)
    }

    func start() {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        step = .flow
        let hint = email.trimmingCharacters(in: .whitespaces)
        task = Task { [engine] in
            do {
                let id = try await engine.addClaude(loginHint: hint.isEmpty ? nil : hint)
                state = .success(id)
            } catch is CancellationError {
                state = .idle
                step = .claudeEmail
            } catch {
                state = AddFlowState.failure(error)
            }
            Self.currentURL = nil
        }
    }

    /// Cancelling the task cancels `awaitCallback`, whose `defer` closes the listener.
    func cancel() {
        task?.cancel()
        task = nil
    }

    func copyLink() {
        guard let url = Self.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}
