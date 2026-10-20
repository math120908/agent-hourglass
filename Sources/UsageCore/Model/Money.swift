/// Minor-unit amount, e.g. 85 / 2000 EUR with exponent 2.
public struct Money: Codable, Sendable, Equatable {
    public var usedMinor: Int
    public var limitMinor: Int?
    public var currency: String
    public var exponent: Int
    /// False when extra usage is switched off (e.g. out of credits).
    public var isEnabled: Bool
    /// Raw server reason when disabled, e.g. "out_of_credits".
    public var disabledReason: String?

    public init(
        usedMinor: Int,
        limitMinor: Int?,
        currency: String,
        exponent: Int,
        isEnabled: Bool = true,
        disabledReason: String? = nil
    ) {
        self.usedMinor = usedMinor
        self.limitMinor = limitMinor
        self.currency = currency
        self.exponent = exponent
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}
