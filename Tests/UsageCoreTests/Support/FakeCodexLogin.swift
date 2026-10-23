import Foundation
@testable import UsageCore

/// Scripted `CodexLoginSource`: returns queued results in order (last repeats) and counts calls.
final class FakeCodexLogin: CodexLoginSource, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<CodexLogin, any Error>]
    private var logins = 0
    private var invalidates = 0
    private(set) var events: [String] = []

    init(_ results: [Result<CodexLogin, any Error>]) { self.results = results }

    var loginCalls: Int { lock.withLock { logins } }
    var invalidateCalls: Int { lock.withLock { invalidates } }

    func login() throws -> CodexLogin {
        let r: Result<CodexLogin, any Error> = lock.withLock {
            logins += 1
            events.append("login")
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        return try r.get()
    }

    func invalidate() {
        lock.withLock {
            invalidates += 1
            events.append("invalidate")
        }
    }
}
