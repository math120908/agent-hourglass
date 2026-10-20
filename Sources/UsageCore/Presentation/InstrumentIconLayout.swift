import Foundation

/// Pure layout for the Instrument (mockup B) menu bar icon: session bar over weekly bar, then session %.
public struct InstrumentIconLayout: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case ink, warning, critical }

    /// Fill fractions in 0...1; nil means no fill is drawn.
    public var sessionFraction: Double?
    public var weeklyFraction: Double?
    public var sessionTone: Tone
    public var weeklyTone: Tone
    /// Always present: "N%" or "--" when stale or unknown.
    public var text: String
    public var dashed: Bool

    public init(_ state: IconState) {
        let outline = state.level == .outline
        func frac(_ p: Int?) -> Double? { outline ? nil : p.map { min(1, max(0, Double($0) / 100)) } }
        func tone(_ p: Int?) -> Tone { guard !outline, let p else { return .ink }; return p >= 90 ? .critical : p >= 75 ? .warning : .ink }
        sessionFraction = frac(state.percent)
        weeklyFraction = frac(state.weekly)
        sessionTone = tone(state.percent)
        weeklyTone = tone(state.weekly)
        text = outline ? "--" : state.percent.map { "\(min(100, max(0, $0)))%" } ?? "--"
        dashed = outline
    }

    /// Template unless any bar carries a severity color.
    public var isTemplate: Bool { sessionTone == .ink && weeklyTone == .ink }
}
