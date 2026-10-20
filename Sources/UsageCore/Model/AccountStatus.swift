import Foundation

public enum AccountStatus: Codable, Sendable, Equatable {
    case fresh
    case stale
    case rateLimited(retryAt: Date)
    case offline
    case needsLogin
    case ghMissing
    case ghLoginRemoved
    case schemaError
    case noData
}
