import Foundation
import Testing
@testable import UsageCore

@Suite struct StateMatrixTests {
    let now = Date(timeIntervalSince1970: 1_800_023_520)
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let all: [AccountStatus] = [.fresh, .stale, .rateLimited(retryAt: Date(timeIntervalSince1970: 1_800_023_820)), .offline,
                                .needsLogin, .ghMissing, .ghLoginRemoved, .schemaError, .noData]

    func snap(_ kind: ProviderKind) -> UsageSnapshot {
        let id = AccountID(kind: kind, remoteID: "x")
        let m = kind == .claude
            ? Meter(kind: .session5h, label: "Session", percentUsed: 40, resetsAt: now.addingTimeInterval(3600), windowLength: .seconds(18000))
            : Meter(kind: .copilotPremium, label: "Premium requests", percentUsed: 40, used: 40, limit: 100)
        return UsageSnapshot(accountID: id, fetchedAt: now.addingTimeInterval(-30), plan: nil, meters: [m])
    }

    @Test func everyStatusHasCopyAndIcon() {
        for kind in [ProviderKind.claude, .copilot] {
            let id = AccountID(kind: kind, remoteID: "x")
            for st in all {
                let card = CardModel.make(snapshot: snap(kind), status: st, kind: kind, now: now, calendar: cal,
                                          locale: Locale(identifier: "en_US_POSIX"), login: "me")
                switch st {
                case .fresh, .noData: #expect(card.statusChip == nil); #expect(!card.isDimmed)
                case .offline: #expect(card.statusChip == nil, "offline is the global banner only"); #expect(card.isDimmed)
                default:
                    #expect(!(card.statusChip ?? "").isEmpty, "\(st) \(kind)")
                    #expect(card.isDimmed)
                }
                #expect(!(card.statusChip ?? "").contains("\u{00B7}"))
                let icon = IconState.make(appState: [id: snap(kind)], statuses: [id: st], menuBarAccount: id, order: [id], now: now)
                if st == .stale || st == .needsLogin { #expect(icon.level == .outline, "\(st)") }
                #expect(icon.caption == (kind == .claude ? "5H" : "PR"))
            }
        }
    }

    @Test func saveFailedChipWins() {
        let card = CardModel.make(snapshot: snap(.claude), status: .stale, kind: .claude, now: now, calendar: cal,
                                  locale: Locale(identifier: "en_US_POSIX"), saveFailed: true)
        #expect(card.statusChip == "Can't save credential")
        #expect(card.isDimmed)
    }
}
