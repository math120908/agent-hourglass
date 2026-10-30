import Foundation
import UsageCore

/// Stable id for a meter inside one account: `Meter.Kind` raw value, plus `:<model>` for
/// weeklyModel and `:<seconds>[:<pool>]` for window (same scheme as `HistoryWriter.meterKey`).
struct MeterKey: Hashable, Codable, Sendable, RawRepresentable {
    let rawValue: String

    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    init(_ m: Meter) {
        switch m.kind {
        case .weeklyModel: rawValue = "\(m.kind.rawValue):\(m.label)"
        case .window: rawValue = "\(m.kind.rawValue):\(m.windowSeconds ?? 0)" + (m.pool.flatMap { $0.isEmpty ? nil : ":\($0)" } ?? "")
        default: rawValue = m.kind.rawValue
        }
    }

    func matches(_ meter: Meter) -> Bool { MeterKey(meter) == self }
}
