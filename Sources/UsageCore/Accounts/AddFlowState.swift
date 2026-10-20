import Foundation

/// State of one Add Account flow (spec §10.6). Only one flow may wait at a time.
public enum AddFlowState: Equatable, Sendable {
    case idle, waiting, success(AccountID), failed(String)

    public var isWaiting: Bool { self == .waiting }

    /// Moves to `.waiting`; returns false when a flow is already waiting.
    public mutating func begin() -> Bool {
        guard !isWaiting else { return false }
        self = .waiting
        return true
    }

    public static func failure(_ error: any Error) -> AddFlowState {
        switch error {
        case AccountServiceError.signInInProgress: .failed("Sign-in already in progress")
        case AccountServiceError.differentAccount, AuthError.differentAccount: .failed("Signed in as a different account")
        case AuthError.cancelled: .failed("Sign-in was cancelled in the browser")
        case AuthError.timeout: .failed("Timed out waiting for the browser")
        case AuthError.stateMismatch: .failed("Sign-in response did not match this request")
        case AuthError.portUnavailable: .failed("Could not open a local port for sign-in")
        default: .failed("Sign-in failed")
        }
    }
}
