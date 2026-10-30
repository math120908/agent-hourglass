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

    /// Google loopback logins: client discovery, then the token and `userinfo` calls' `ProviderError`s.
    public static func googleFailure(_ error: any Error) -> AddFlowState {
        switch error {
        case GoogleOAuthError.clientUnavailable: .failed("Install Antigravity or the agy CLI first")
        case GoogleOAuthError.clientRejected: .failed("Google rejected the Antigravity client. Retry")
        case ProviderError.invalidGrant: .failed("Google did not accept the sign-in code. Retry")
        case ProviderError.unauthorized: .failed("The new sign-in was rejected. Retry")
        case let ProviderError.http(status, _, _): .failed("Google answered HTTP \(status). Retry")
        case ProviderError.rateLimited: .failed("Too many sign-in attempts. Wait a minute and retry")
        case ProviderError.schema: .failed("Unexpected answer from Google")
        case ProviderError.transport: .failed("Network error during sign-in. Check the connection and retry")
        case ProviderError.hostNotAllowed, ProviderError.redirectRefused: .failed("Google redirected the sign-in somewhere unexpected")
        case AccountServiceError.missingAccountID: .failed("The sign-in did not identify an account")
        default: failure(error)
        }
    }

    /// Device-code logins (Grok): the poll's RFC 8628 outcomes, then the `userinfo` call's `ProviderError`s.
    public static func deviceFailure(_ error: any Error) -> AddFlowState {
        switch error {
        case DeviceFlowError.expired: .failed("The code expired. Retry for a new one")
        case DeviceFlowError.denied: .failed("Sign-in was denied")
        case let DeviceFlowError.unexpected(status), let ProviderError.http(status, _, _):
            .failed("The sign-in server answered HTTP \(status). Retry")
        case ProviderError.unauthorized, ProviderError.invalidGrant: .failed("The new sign-in was rejected. Retry")
        case ProviderError.schema: .failed("Unexpected answer from the sign-in server")
        case ProviderError.transport: .failed("Network error during sign-in. Check the connection and retry")
        case ProviderError.rateLimited: .failed("Too many sign-in attempts. Wait a minute and retry")
        case AccountServiceError.missingAccountID: .failed("The sign-in did not identify an account")
        default: failure(error)
        }
    }
}
