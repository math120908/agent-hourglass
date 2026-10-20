import Foundation

/// Locale-independent text helpers for the card model. No string here may contain U+00B7.
enum Formatting {
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }

    static func minor(_ amount: Int, exponent: Int) -> String {
        guard exponent > 0 else { return String(amount) }
        var scale = 1
        for _ in 0..<exponent { scale *= 10 }
        let frac = String(abs(amount) % scale)
        let padded = String(repeating: "0", count: exponent - frac.count) + frac
        return "\(amount < 0 ? "-" : "")\(abs(amount) / scale).\(padded)"
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func pattern(_ fmt: String, _ date: Date, _ calendar: Calendar, _ locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = fmt
        return f.string(from: date)
    }

    /// "1 h 38 min", "38 min", "2 d 3 h".
    static func span(_ seconds: TimeInterval) -> String {
        let mins = max(0, Int((seconds / 60).rounded(.up)))
        let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
        if d > 0 { return h > 0 ? "\(d) d \(h) h" : "\(d) d" }
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        return "\(m) min"
    }

    static func planTag(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let words = raw.split(whereSeparator: { $0 == "_" || $0 == " " }).map(String.init)
        guard let first = words.first else { return nil }
        return ([first.prefix(1).uppercased() + first.dropFirst().lowercased()] + words.dropFirst().map { $0.lowercased() })
            .joined(separator: " ")
    }
}
