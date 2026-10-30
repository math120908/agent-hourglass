import Foundation

/// The provider is signed in but has no trustworthy quota to report. Maps to `AccountStatus.quotaUnavailable`.
public enum QuotaError: Error, Equatable, Sendable {
    case unavailable
}
