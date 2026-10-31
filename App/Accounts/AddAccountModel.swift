import AppKit
import Observation
import UsageCore

/// Drives the Add Account sheet. One flow at a time across all windows.
@MainActor @Observable
final class AddAccountModel {
    enum Step { case provider, claudeEmail, copilotPick, flow }

    /// Copilot pick list; nil while loading, empty when gh is missing or has no github.com login.
    var logins: [String]?

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
        resetFlow()
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

    /// Loads github.com logins from `gh auth status`. gh missing shows the empty state.
    func loadLogins() {
        step = .copilotPick
        logins = nil
        Task { [engine] in
            logins = (try? await engine.copilotLogins()) ?? []
        }
    }

    private var copilotLogin: String?
    var isCopilot: Bool { copilotLogin != nil }

    private(set) var isCodex = false

    private(set) var isClaudeCode = false

    private(set) var isGoogle = false

    private(set) var isGrok = false

    private(set) var isElevenLabs = false
    /// The Grok device code being waited on; shown in the sheet and copied by "Copy code".
    private(set) var devicePrompt: DeviceCodePrompt?

    /// Adds Claude Code (local, read-only): reads Claude Code's own Keychain login on each poll.
    func addClaudeCodeLocal() {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        resetFlow()
        isClaudeCode = true
        step = .flow
        task = Task { [engine] in
            do {
                state = .success(try await engine.addClaudeCodeLocal())
            } catch {
                state = AddFlowState.failure(error)
            }
        }
    }

    func retry() {
        if isClaudeCode { addClaudeCodeLocal() } else if isGoogle { addGoogle() } else if isGrok { addGrok() } else if isElevenLabs { addElevenLabs() } else if isCodex { addCodex() } else if let copilotLogin { addCopilot(copilotLogin) } else { start() }
    }

    /// Adds the Codex CLI's ChatGPT login from ~/.codex/auth.json (read-only, no browser).
    func addCodex() {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        resetFlow()
        isCodex = true
        step = .flow
        task = Task { [engine] in
            do {
                state = .success(try await engine.addCodex())
            } catch is CodexAuthError {
                state = .failed("Run `codex` and sign in with ChatGPT first")
            } catch {
                state = AddFlowState.failure(error)
            }
        }
    }

    /// Google AI login: loopback PKCE in the browser as the Antigravity client found on this Mac.
    func addGoogle() {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        resetFlow()
        isGoogle = true
        step = .flow
        task = Task { [engine] in
            do {
                state = .success(try await engine.addGoogle())
            } catch is CancellationError {
                state = .idle
                step = .provider
            } catch {
                // A cancelled URLSession call surfaces as ProviderError.transport, not CancellationError.
                if Task.isCancelled {
                    state = .idle
                    step = .provider
                } else {
                    state = AddFlowState.googleFailure(error)
                }
            }
            Self.currentURL = nil
        }
    }

    /// Grok device-code login: show and open the code, poll until it is approved, then add the account.
    func addGrok() {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        resetFlow()
        isGrok = true
        step = .flow
        task = Task { [engine] in
            do {
                let auth = GrokDeviceAuth(http: HTTPClient())
                let p = try await auth.start()
                try Task.checkCancellation()
                devicePrompt = p
                Self.open(p.verificationURL)
                let cred = try await auth.poll(p)
                state = .success(try await engine.addGrok(credential: cred))
            } catch is CancellationError {
                state = .idle
                step = .provider
            } catch {
                // Cancel during start() or userinfo surfaces as a transport error; it is still a cancel.
                if Task.isCancelled {
                    state = .idle
                    step = .provider
                } else {
                    state = AddFlowState.deviceFailure(error)
                }
            }
            devicePrompt = nil
            Self.currentURL = nil
        }
    }

    /// ElevenLabs login: sign in inside a throwaway web view, then mint a fresh ID token from the
    /// Firebase refresh token the page stored, and add the account.
    func addElevenLabs() {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        resetFlow()
        isElevenLabs = true
        step = .flow
        task = Task { [engine] in
            do {
                let session = try await ElevenLabsWebLogin().signIn()
                try Task.checkCancellation()
                guard let cred = try await ElevenLabsProvider().refresh(credential: session.seedCredential, http: HTTPClient()) else {
                    throw ProviderError.invalidGrant
                }
                state = .success(try await engine.addElevenLabs(credential: cred))
            } catch is CancellationError {
                state = .idle
                step = .provider
            } catch {
                if Task.isCancelled {
                    state = .idle
                    step = .provider
                } else {
                    state = AddFlowState.deviceFailure(error)
                }
            }
        }
    }

    func addCopilot(_ login: String) {
        guard state.begin() else {
            state = .failed("Sign-in already in progress")
            return
        }
        resetFlow()
        copilotLogin = login
        step = .flow
        task = Task { [engine] in
            do {
                state = .success(try await engine.addCopilot(login: login))
            } catch {
                state = AddFlowState.failure(error)
            }
        }
    }

    /// Clears every provider flag so the sheet and `retry()` follow only the flow that just started.
    private func resetFlow() {
        copilotLogin = nil
        isCodex = false
        isClaudeCode = false
        isGoogle = false
        isGrok = false
        isElevenLabs = false
        devicePrompt = nil
    }

    /// Cancelling the task cancels `awaitCallback`, whose `defer` closes the listener.
    func cancel() {
        task?.cancel()
        task = nil
        devicePrompt = nil
    }

    func copyLink() {
        guard let url = Self.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func copyCode() {
        guard let code = devicePrompt?.userCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}
