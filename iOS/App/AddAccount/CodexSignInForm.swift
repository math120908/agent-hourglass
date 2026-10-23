import Foundation

/// View-side state of the Codex device-code sign-in: what the user has done on this screen.
/// The server outcome lives in `DeviceCodeFlowModel.State`; step states are pure functions of both.
struct CodexSignInForm: Equatable {
    typealias Step = SignInStep
    enum WaitLine: Equatable { case finishing, stillWaiting }

    /// After this long back on the sheet with no result, the step 3 line suggests re-opening.
    static let stillWaitingAfter: TimeInterval = 30

    var copied = false
    /// The verification page was opened at least once.
    var opened = false
    /// Last return from the browser while waiting; restarts after each Open.
    var returnedAt: Date?
    /// Opened since the last return, so the next active phase counts as coming back.
    var awaitingReturn = false

    var stillWaitingAt: Date? { returnedAt?.addingTimeInterval(Self.stillWaitingAfter) }

    /// Rows 1-3. Finished states show the whole checklist done above the outcome row.
    func steps(_ state: DeviceCodeFlowModel.State) -> [Step] {
        switch state {
        case .starting: return [.current, .todo, .todo]
        case .expired, .failed, .success: return [.done, .done, .done]
        case .waiting:
            if returnedAt != nil { return [.done, .done, .current] }
            if copied || opened { return [.done, .current, .todo] }
            return [.current, .todo, .todo]
        }
    }

    func copyProminent(_ state: DeviceCodeFlowModel.State) -> Bool {
        guard case .waiting = state else { return false }
        return steps(state)[0] == .current
    }

    func openProminent(_ state: DeviceCodeFlowModel.State) -> Bool {
        guard case .waiting = state else { return false }
        return steps(state)[1] == .current && !opened
    }

    /// Step 3 line: shown only once the user is back and the poll is still running.
    func waitLine(_ state: DeviceCodeFlowModel.State, now: Date) -> WaitLine? {
        guard case .waiting = state, let at = stillWaitingAt else { return nil }
        return now >= at ? .stillWaiting : .finishing
    }

    mutating func copy() { copied = true }

    mutating func open() {
        opened = true
        awaitingReturn = true
    }

    /// The scene became active. Counts only after an Open and while the poll runs.
    mutating func cameBack(at now: Date, state: DeviceCodeFlowModel.State) {
        guard case .waiting = state, awaitingReturn else { return }
        returnedAt = now
        awaitingReturn = false
    }

    mutating func reset() { self = Self() }
}
