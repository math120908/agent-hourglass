import Foundation
import Testing
@testable import UsageCore

struct DiagnosticsTests {
    @Test func noTokensOrIds() {
        let id = AccountID(kind: .claude, remoteID: "secret-remote-uuid-1234")
        let snap = UsageSnapshot(accountID: id, fetchedAt: Date(timeIntervalSince1970: 100), meters: [], rawUnknownKeys: ["new_field"])
        let out = Diagnostics.report(
            app: "1.0 (abc1234)",
            accounts: [
                .init(id: id, kind: .claude, status: .fresh, snapshot: snap),
                .init(id: AccountID(kind: .copilot, remoteID: "octo-login"), kind: .copilot, status: .needsLogin, snapshot: nil),
            ],
            isOffline: false,
            interval: .seconds(60),
            now: Date(timeIntervalSince1970: 160)
        )
        #expect(!out.contains("secret-remote-uuid"))
        #expect(!out.contains("octo-login"))
        #expect(out.contains(Diagnostics.hash(id)))
        #expect(out.contains("unknownKeys=[new_field]"))
        #expect(out.contains("status=needsLogin"))
        #expect(out.contains("age=60s"))
    }

    @Test func quotaUnavailableStatusName() {
        #expect(Diagnostics.statusName(.quotaUnavailable) == "quotaUnavailable")
    }
}
