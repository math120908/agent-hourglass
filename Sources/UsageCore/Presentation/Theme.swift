import Foundation

/// Visual theme. Glass is the default; Instrument is mockup B.
public enum Theme: String, CaseIterable, Codable, Sendable {
    case glass
    case instrument

    public static let `default`: Theme = .glass

    /// Unknown or missing stored values fall back to the default.
    public init(storedValue: String?) {
        self = storedValue.flatMap(Theme.init(rawValue:)) ?? .default
    }
}

