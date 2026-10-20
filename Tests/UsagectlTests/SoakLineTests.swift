import Foundation
import Testing
import UsageCore
@testable import usagectl

@Suite struct SoakLineTests {
    let at = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func successLine() {
        let id = AccountID(kind: .claude, remoteID: "abc")
        let snap = UsageSnapshot(accountID: id, fetchedAt: at, meters: [
            Meter(kind: .session5h, label: "s", percentUsed: 12.5),
            Meter(kind: .weeklyAll, label: "w", percentUsed: 40),
        ])
        let line = SoakLine.format(at: at, outcome: .success(snap), count429: 0)
        #expect(line == "2027-01-15T08:00:00Z status=fresh http=200 session=12.5 weekly=40.0 n429=0")
    }

    @Test func rateLimitedLine() {
        let line = SoakLine.format(at: at, outcome: .failure(.rateLimited(retryAt: at)), count429: 3)
        #expect(line.hasSuffix("status=rateLimited http=429 session=- weekly=- n429=3 wait=0s"))
    }

    @Test func logFileIs0600AndAppends() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soak-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let f = try SoakLogFile(url: url)
        f.append("a"); f.append("b")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(try String(contentsOf: url, encoding: .utf8) == "a\nb\n")
    }
}
