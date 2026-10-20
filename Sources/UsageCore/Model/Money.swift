/// Minor-unit amount, e.g. 85 / 2000 EUR with exponent 2.
public struct Money: Codable, Sendable, Equatable {
    public var usedMinor: Int
    public var limitMinor: Int?
    public var currency: String
    public var exponent: Int

    public init(usedMinor: Int, limitMinor: Int?, currency: String, exponent: Int) {
        self.usedMinor = usedMinor
        self.limitMinor = limitMinor
        self.currency = currency
        self.exponent = exponent
    }
}
