import Foundation

/// Single-flight refresh: concurrent callers share one in-flight refresh task.
public actor RefreshLock {
    private var inFlight: Task<Credential, Error>?

    public init() {}

    public func refresh(_ work: @escaping @Sendable () async throws -> Credential) async throws -> Credential {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await work() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
