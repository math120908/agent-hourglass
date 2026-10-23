import Foundation
@testable import UsageCore

/// Scripted `CopilotTokenSource`: returns queued results in order (last one repeats).
final class FakeCopilotTokens: CopilotTokenSource, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Secret, any Error>]
    private var _tokenCalls = 0
    private var _invalidated: [String] = []

    init(_ results: [Result<Secret, any Error>]) { self.results = results }

    var tokenCalls: Int { lock.withLock { _tokenCalls } }
    var invalidated: [String] { lock.withLock { _invalidated } }

    func token(for login: String) async throws -> Secret {
        let r: Result<Secret, any Error> = lock.withLock {
            _tokenCalls += 1
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        return try r.get()
    }

    func invalidate(_ login: String) { lock.withLock { _invalidated.append(login) } }
}
