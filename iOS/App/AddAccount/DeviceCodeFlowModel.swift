import Foundation
import Observation
import os
import UsageCore

/// Drives a device-code sign-in: `start` fetches a prompt, `complete` polls until the user approves.
/// Generic over the start/complete pair so any device-code provider can reuse it.
@MainActor @Observable final class DeviceCodeFlowModel {
    enum State: Equatable {
        case starting
        case waiting(DeviceCodePrompt)
        case expired
        case success(AccountID)
        case failed(String)
    }

    let title: String
    let kind: ProviderKind
    /// Verification host named on the sheet ("Open …" and the lead line).
    let host: String
    let lead: String
    private(set) var state: State = .starting

    @ObservationIgnored private let start: @Sendable () async throws -> DeviceCodePrompt
    @ObservationIgnored private let complete: @Sendable (DeviceCodePrompt) async throws -> AccountID
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let wake: (@Sendable () -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        title: String,
        kind: ProviderKind = .codex,
        host: String = "auth.openai.com",
        lead: String? = nil,
        start: @escaping @Sendable () async throws -> DeviceCodePrompt,
        complete: @escaping @Sendable (DeviceCodePrompt) async throws -> AccountID,
        now: @escaping @Sendable () -> Date = { Date() },
        wake: (@Sendable () -> Void)? = nil,
    ) {
        self.title = title
        self.kind = kind
        self.host = host
        // Broken by hand into two balanced lines; the natural wrap left "back here." alone.
        self.lead = lead ?? "Enter this code on \(host),\nthen come back here."
        self.start = start
        self.complete = complete
        self.now = now
        self.wake = wake
    }

    /// Fixed-state init for previews and snapshots.
    convenience init(
        title: String,
        kind: ProviderKind = .codex,
        host: String = "auth.openai.com",
        lead: String? = nil,
        state: State,
    ) {
        self.init(
            title: title,
            kind: kind,
            host: host,
            lead: lead,
            start: { throw CancellationError() },
            complete: { _ in throw CancellationError() },
        )
        self.state = state
    }

    func begin() {
        task?.cancel()
        state = .starting
        task = Task { await run() }
    }

    func restart() { begin() }

    /// The app is back in the foreground: let the poll run now if its interval has elapsed.
    func foreground() {
        if case .waiting = state { wake?() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private nonisolated static let log = Logger(subsystem: "cc.kuoc.agent-hourglass", category: "DeviceCodeFlow")

    /// Type name plus, for the secret-free error enums, the case (status codes, hosts, key names).
    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case let e as ProviderError: "ProviderError \(e.description)"
        case let e as DeviceFlowError: "DeviceFlowError \(e)"
        default: String(describing: type(of: error))
        }
    }

    private enum Outcome: Sendable {
        case done(AccountID)
        case expired
        case failed
    }

    private func run() async {
        let prompt: DeviceCodePrompt
        do {
            prompt = try await start()
        } catch {
            if !Task.isCancelled { state = .failed("Couldn't get a code") }
            return
        }
        guard !Task.isCancelled else { return }
        state = .waiting(prompt)
        let complete = self.complete
        let remaining = prompt.expiresAt.timeIntervalSince(now())
        let outcome: Outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                do { return .done(try await complete(prompt)) } catch {
                    Self.log.error("device login complete failed: \(Self.describe(error), privacy: .public)")
                    return .failed
                }
            }
            group.addTask {
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                return .expired
            }
            let first = await group.next() ?? .failed
            group.cancelAll()
            return first
        }
        guard !Task.isCancelled else { return }
        switch outcome {
        case .done(let id): state = .success(id)
        case .expired: state = .expired
        case .failed: state = now() >= prompt.expiresAt ? .expired : .failed("Sign-in failed")
        }
    }
}
