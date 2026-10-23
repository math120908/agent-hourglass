import Foundation

/// User display preferences shared by the iOS app and its widgets.
public struct MeterDisplayOptions: Sendable, Equatable {
    public var showRemaining: Bool
    public var countdown: Bool
    public var use24Hour: Bool
    public var calendar: Calendar
    public var locale: Locale

    public init(
        showRemaining: Bool = false,
        countdown: Bool = false,
        use24Hour: Bool = true,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.showRemaining = showRemaining
        self.countdown = countdown
        self.use24Hour = use24Hour
        self.calendar = calendar
        self.locale = locale
    }
}

/// Portable presentation of one meter. Every percent, reset and age string on iOS comes from here.
public struct MeterDisplay: Sendable, Equatable {
    public var label: String
    public var percentText: String
    public var isRemaining: Bool
    public var fraction: Double?
    public var paceTick: Double?
    public var paceText: String?
    public var resetText: String
    public var resetShort: String?
    public var detailText: String?
    public var severity: Meter.Severity

    public static func make(_ meter: Meter, now: Date, options: MeterDisplayOptions) -> MeterDisplay {
        let row = CardModel.Ctx(now: now, calendar: options.calendar, locale: options.locale).row(meter)
        let (resetText, resetShort) = reset(meter, now: now, options: options)
        var d = MeterDisplay(
            label: row.label,
            percentText: row.percentText,
            isRemaining: options.showRemaining,
            fraction: row.fraction,
            paceTick: row.paceTick,
            paceText: row.paceText,
            resetText: resetText,
            resetShort: resetShort,
            detailText: row.detailText,
            severity: row.severity
        )
        if options.showRemaining {
            d.paceTick = row.paceTick.map { 1 - $0 }
            if let used = row.fraction {
                d.fraction = 1 - used
                d.percentText = "\(Int(((1 - used) * 100).rounded()))%"
            }
        }
        return d
    }

    public static func ageText(fetchedAt: Date, now: Date, options: MeterDisplayOptions) -> String {
        let age = now.timeIntervalSince(fetchedAt)
        if age < 60 { return "Updated just now" }
        if age < 3600 { return "Updated \(Int(age / 60)) min ago" }
        return "Updated " + dayOrClock(fetchedAt, now: now, options: options)
    }

    public static func ageShort(fetchedAt: Date, now: Date, options: MeterDisplayOptions) -> String {
        let age = now.timeIntervalSince(fetchedAt)
        if age < 60 { return "now" }
        if age < 3600 { return "\(Int(age / 60))m" }
        return dayOrClock(fetchedAt, now: now, options: options)
    }

    public static func visibleMeters(_ snapshot: UsageSnapshot?) -> [Meter] {
        (snapshot?.meters ?? []).filter(CardModel.isVisible)
    }

    // MARK: - Private

    static func reset(_ m: Meter, now: Date, options: MeterDisplayOptions) -> (String, String?) {
        guard let at = m.resetsAt else { return ("Not started", nil) }
        if at <= now { return ("Resetting…", nil) }
        if options.countdown {
            let s = countdown(at.timeIntervalSince(now))
            return ("Resets in " + s, s)
        }
        let s = resetClock(at, now: now, options: options)
        return ("Resets " + s, s)
    }

    /// "3d 8h", "1h 32m", "15d", "2m"; minutes rounded up.
    static func countdown(_ seconds: TimeInterval) -> String {
        let mins = max(0, Int((seconds / 60).rounded(.up)))
        let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// Same day: time. Within 7 days: weekday + time. Later: "MMM d".
    static func resetClock(_ at: Date, now: Date, options: MeterDisplayOptions) -> String {
        let cal = options.calendar
        if cal.isDate(at, inSameDayAs: now) { return clock(at, options) }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: at)).day ?? Int.max
        if days < 7 { return format("EEE", at, options) + " " + clock(at, options) }
        return format("MMM d", at, options)
    }

    static func dayOrClock(_ at: Date, now: Date, options: MeterDisplayOptions) -> String {
        options.calendar.isDate(at, inSameDayAs: now) ? clock(at, options) : format("MMM d", at, options)
    }

    static func clock(_ date: Date, _ options: MeterDisplayOptions) -> String {
        format(options.use24Hour ? "HH:mm" : "h:mm a", date, options)
    }

    static func format(_ fmt: String, _ date: Date, _ options: MeterDisplayOptions) -> String {
        let f = DateFormatter()
        f.calendar = options.calendar
        f.timeZone = options.calendar.timeZone
        f.locale = options.locale
        f.dateFormat = fmt
        return f.string(from: date)
    }
}
