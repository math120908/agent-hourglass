import Foundation
import Testing
@testable import UsageCore
@testable import UsageCoreMac

/// Reads Tests/UsageCoreTests/Fixtures/<name>.json; one fixture directory shared with UsageCoreTests.
func fixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("UsageCoreTests/Fixtures/\(name).json")
    return try Data(contentsOf: url)
}

/// Records requests; returns queued statuses (last repeats) with the codex-go body.
final class CodexTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int]
    private(set) var requests: [URLRequest] = []
    init(_ statuses: [Int] = [200]) { self.statuses = statuses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let status: Int = lock.withLock {
            requests.append(request)
            return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        }
        return (try fixture("codex-go"), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    var count: Int { lock.withLock { requests.count } }
}

final class SvcEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _e: [String] = []
    func add(_ s: String) { lock.withLock { _e.append(s) } }
    var all: [String] { lock.withLock { _e } }
}

final class SvcFakeHistory: HistoryDeleting, @unchecked Sendable {
    let log: SvcEventLog
    init(log: SvcEventLog) { self.log = log }
    func deleteAccount(_ id: AccountID) async throws { log.add("history-delete:\(id.rawValue)") }
}
