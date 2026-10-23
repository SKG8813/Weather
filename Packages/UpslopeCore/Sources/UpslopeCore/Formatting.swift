import Foundation

/// Display strings shared by the app, widgets and alerts. US units throughout.
public enum Fmt {
    public static func inches(_ x: Double) -> String {
        if x <= 0 { return "0″" }
        if x < 0.1 { return "<0.1″" }
        if x < 10 { return String(format: "%.1f″", x).replacingOccurrences(of: ".0″", with: "″") }
        return "\(Int(x.rounded()))″"
    }

    public static func inchRange(_ x: Double) -> String {
        // Snow forecasts read better as ranges ("3–5″") once they're past an inch.
        guard x >= 1.5 else { return inches(x) }
        let lo = max(1, Int((x * 0.75).rounded()))
        let hi = max(lo + 1, Int((x * 1.25).rounded()))
        return "\(lo)–\(hi)″"
    }

    public static func rate(_ x: Double) -> String {
        if x < 0.1 { return "<0.1″/hr" }
        return String(format: "%.1f″/hr", x)
    }

    public static func minutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    /// "12m", "1h5m". Fits in lock screen widgets.
    public static func shortMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h\(r)m"
    }

    public static func temp(_ f: Double) -> String { "\(Int(f.rounded()))°" }

    public static func percent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }

    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "h:mm"
        return f.string(from: date)
    }

    public static func weekday(_ date: Date, timeZone: TimeZone = .current, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    public static func compass(_ bearing: Double?) -> String {
        guard let b = bearing else { return "" }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((b.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return dirs[i]
    }

    public static func feet(_ ft: Double) -> String {
        let rounded = Int((ft / 100).rounded()) * 100
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return (f.string(from: NSNumber(value: rounded)) ?? "\(rounded)") + "′"
    }
}

/// Headline and widget lines for a next-hour state.
public enum NextHourText {
    /// "Snow in 12 minutes." / "Rain now." / "Dry for the hour."
    public static func headline(_ state: NextHourState) -> String {
        switch state {
        case .dry:
            return "Dry for the hour."
        case .upcoming(let e, let m):
            if m <= 1 { return "\(e.type.noun) any second." }
            return "\(e.type.noun) in \(m) minutes."
        case .ongoing(let e, let left):
            if e.continuesPastWindow { return "\(e.type.noun) now. Sticking around." }
            return "\(e.type.noun) now, ~\(left) min left."
        }
    }

    /// Short line for the rectangular lock screen widget: "Snow in 12m".
    public static func compact(_ state: NextHourState) -> String {
        switch state {
        case .dry: return "Dry for the hour"
        case .upcoming(let e, let m): return "\(e.type.noun) in \(Fmt.shortMinutes(m))"
        case .ongoing(let e, let left):
            return e.continuesPastWindow ? "\(e.type.noun) now" : "\(e.type.noun) · \(Fmt.shortMinutes(left)) left"
        }
    }

    /// One line for the inline widget above the clock: "Snow 7:54 · 40 min".
    public static func inline(_ state: NextHourState, timeZone: TimeZone = .current) -> String {
        switch state {
        case .dry: return "Dry for the hour"
        case .upcoming(let e, _):
            return "\(e.type.noun) \(Fmt.clock(e.start, timeZone: timeZone)) · \(duration(e))"
        case .ongoing(let e, _):
            return e.continuesPastWindow ? "\(e.type.noun) now · 1 hr+" : "\(e.type.noun) until \(Fmt.clock(e.end, timeZone: timeZone))"
        }
    }

    public static func duration(_ e: PrecipEvent) -> String {
        e.continuesPastWindow ? "1 hr+" : "~\(Fmt.minutes(e.durationMinutes))"
    }

    /// "Snow in 12 min · ~40 min · up to 1.1″/hr"
    public static func alertTitle(_ state: NextHourState) -> String? {
        switch state {
        case .dry: return nil
        case .upcoming(let e, let m):
            return "\(e.type.noun) in \(Fmt.minutes(m)) · \(duration(e)) · up to \(Fmt.rate(e.peakRate))"
        case .ongoing(let e, let left):
            let rest = e.continuesPastWindow ? "for the next hour+" : "for ~\(Fmt.minutes(left))"
            return "\(e.type.noun) now \(rest) · up to \(Fmt.rate(e.peakRate))"
        }
    }
}
