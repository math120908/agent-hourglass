import Foundation

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var accountID: AccountID
    public var fetchedAt: Date
    public var plan: String?
    public var meters: [Meter]
    public var spend: Money?
    public var rawUnknownKeys: [String]

    public init(
        accountID: AccountID,
        fetchedAt: Date,
        plan: String? = nil,
        meters: [Meter],
        spend: Money? = nil,
        rawUnknownKeys: [String] = []
    ) {
        self.accountID = accountID
        self.fetchedAt = fetchedAt
        self.plan = plan
        self.meters = meters
        self.spend = spend
        self.rawUnknownKeys = rawUnknownKeys
    }
}
