import Foundation
import Observation
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
    private(set) var state: State = .starting

    @ObservationIgnored private let start: @Sendable () async throws -> DeviceCodePrompt
    @ObservationIgnored private let complete: @Sendable (DeviceCodePrompt) async throws -> AccountID
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        title: String,
        start: @escaping @Sendable () async throws -> DeviceCodePrompt,
        complete: @escaping @Sendable (DeviceCodePrompt) async throws -> AccountID,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.title = title
        self.start = start
        self.complete = complete
        self.now = now
    }

    /// Fixed-state init for previews and snapshots.
    convenience init(title: String, state: State) {
        self.init(title: title, start: { throw CancellationError() }, complete: { _ in throw CancellationError() })
        self.state = state
    }

    func begin() {
        task?.cancel()
        state = .starting
        task = Task { await run() }
    }

    func restart() { begin() }

    func cancel() {
        task?.cancel()
        task = nil
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
                do { return .done(try await complete(prompt)) } catch { return .failed }
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
