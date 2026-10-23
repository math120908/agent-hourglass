import Foundation
import Testing
@testable import UsageCore

private let ghToken = "gho_" + String(repeating: "y", count: 36)

/// Mock transport returning queued statuses (last one repeats); `/user` gets a numeric id.
private final class QueueTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int]
    private(set) var paths: [String] = []
    private(set) var authHeaders: [String?] = []
    let userID: Int
    init(_ statuses: [Int] = [200], userID: Int = 4242) { self.statuses = statuses; self.userID = userID }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let status: Int = lock.withLock {
            paths.append(path)
            authHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
            if path == "/user" { return 200 }
            return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
        }
        let body = path == "/user"
            ? Data(#"{"login":"renamed","id":\#(userID)}"#.utf8)
            : try fixture("copilot-individual")
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
    var copilotCalls: Int { lock.withLock { paths.filter { $0 != "/user" }.count } }
    var lastAuth: String? { lock.withLock { authHeaders.last ?? nil } }
}

struct CopilotTokenSourceTests {
    let id = AccountID(kind: .copilot, remoteID: "4242")

    private func client(_ src: any CopilotTokenSource, _ t: QueueTransport) -> AccountClient {
        AccountClient(
            id: id,
            provider: CopilotProvider(),
            http: HTTPClient(transport: t),
            store: InMemoryCredentialStore(),
            clock: ContinuousClock(),
            now: { Date() },
            tokenSource: src,
            login: "alice"
        )
    }

    @Test func fakeSourceFetchesWithToken() async throws {
        let fake = FakeCopilotTokens([.success(Secret(ghToken))])
        let t = QueueTransport()
        guard case .success = await client(fake, t).fetch() else { Issue.record("expected success"); return }
        #expect(fake.tokenCalls == 1)
        #expect(t.lastAuth == "Bearer \(ghToken)")
    }

    @Test func unauthorizedInvalidatesAndRetriesOnce() async throws {
        let fake = FakeCopilotTokens([.success(Secret(ghToken))])
        guard case .success = await client(fake, QueueTransport([401, 200])).fetch() else {
            Issue.record("expected success")
            return
        }
        #expect(fake.invalidated == ["alice"])
        #expect(fake.tokenCalls == 2)
    }

    @Test func secondUnauthorizedNeedsLogin() async throws {
        let fake = FakeCopilotTokens([.success(Secret(ghToken))])
        let t = QueueTransport([401])
        #expect(await client(fake, t).fetch() == .failure(.needsLogin))
        #expect(t.copilotCalls == 2)
    }

    @Test func ghErrorsMapToStatuses() async throws {
        let missing = FakeCopilotTokens([.failure(GhError.missing)])
        #expect(await client(missing, QueueTransport()).fetch() == .failure(.ghMissing))
        let removed = FakeCopilotTokens([.failure(GhError.loginRemoved)])
        #expect(await client(removed, QueueTransport()).fetch() == .failure(.ghLoginRemoved))
    }

    private func service(_ src: (any CopilotTokenSource)?) throws -> AccountService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cpts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = InMemoryCredentialStore()
        let http = HTTPClient(transport: QueueTransport())
        let poller = Poller(clients: [], clock: ContinuousClock(), now: { Date() }, jitter: { 0 }) { _, _ in }
        return AccountService(
            registry: AccountRegistry(directory: dir),
            store: store,
            poller: poller,
            history: SvcFakeHistory(log: SvcEventLog()),
            claudeLogin: { _, _ in throw AccountServiceError.unknownAccount },
            makeClient: { id in
                AccountClient(id: id, provider: CopilotProvider(), http: http, store: store, clock: ContinuousClock(), now: { Date() }, tokenSource: src, login: "alice")
            },
            ghTokens: src,
            http: http
        )
    }

    @Test func addCopilotUsesProtocol() async throws {
        let fake = FakeCopilotTokens([.success(Secret(ghToken))])
        let added = try await service(fake).addCopilot(login: "alice")
        #expect(added == AccountID(kind: .copilot, remoteID: "4242"))
        await #expect(throws: GhError.missing) { try await service(nil).addCopilot(login: "alice") }
    }
}
