import Foundation

/// A day summarized for planning: three parts of the day, the wet windows,
/// and the handful of numbers that matter. Deliberately not an hourly list.
public struct DayPlan: Sendable, Equatable {
    public struct Part: Sendable, Equatable {
        public enum Name: String, Sendable { case morning = "Morning", afternoon = "Afternoon", night = "Night" }
        public var name: Name
        public var start: Date
        public var end: Date
        /// Warmest temperature for morning/afternoon, coldest for night.
        public var temperature: Double
        public var symbol: DaySymbol
        /// 0...1, highest hourly chance in the part.
        public var chance: Double
        public var rain: Double
        public var snow: Double
        public var wind: Double
        public var windBearing: Double?

        public var isDry: Bool { rain < 0.02 && snow < 0.1 }
    }

    public struct WetWindow: Sendable, Equatable {
        public var start: Date
        public var end: Date
        public var type: PrecipType
        public var peak: Date
    }

    public var date: Date
    public var parts: [Part]
    public var windows: [WetWindow]
    public var high: Double
    public var highAt: Date?
    public var low: Double
    public var lowAt: Date?
    public var feelsLikeLow: Double?
    public var maxGust: Double?
    public var rainTotal: Double
    public var snowTotal: Double
    public var sunrise: Date?
    public var sunset: Date?
    /// "Rain turns to snow ~4 pm"
    public var changeover: String?
    /// "Dry morning, then snow 2–9 pm. 2–4″ of snow, heaviest around 5 pm."
    public var summary: String
}

public enum DayPlanner {
    /// Part boundaries, in hours after local midnight. Night runs to 6 am the next day.
    public static let morning = 6..<12
    public static let afternoon = 12..<18
    public static let night = 18..<30
    /// An hour counts as wet at this much liquid.
    public static let wetHour = 0.01

    public static func plan(for day: DayForecast, hours: [HourPoint], timeZone: TimeZone) -> DayPlan {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let midnight = cal.startOfDay(for: day.date)
        func at(_ h: Int) -> Date { midnight.addingTimeInterval(Double(h) * 3600) }
        func hoursIn(_ r: Range<Int>) -> [HourPoint] {
            hours.filter { $0.time >= at(r.lowerBound) && $0.time < at(r.upperBound) }
        }

        let parts: [DayPlan.Part] = [(DayPlan.Part.Name.morning, morning), (.afternoon, afternoon), (.night, night)].compactMap { name, r in
            let hs = hoursIn(r)
            guard !hs.isEmpty else { return nil }
            let rain = hs.reduce(0) { $0 + $1.rain }
            let snow = hs.reduce(0) { $0 + $1.snowfall }
            let windiest = hs.max { $0.windSpeed < $1.windSpeed }
            let clouds = hs.compactMap(\.cloudCover)
            return DayPlan.Part(
                name: name, start: at(r.lowerBound), end: at(r.upperBound),
                temperature: name == .night ? hs.map(\.temperature).min()! : hs.map(\.temperature).max()!,
                symbol: symbol(rain: rain, snow: snow, cloud: clouds.isEmpty ? nil : clouds.reduce(0, +) / Double(clouds.count), night: name == .night),
                chance: hs.map(\.probability).max() ?? 0,
                rain: rain, snow: snow,
                wind: windiest?.windSpeed ?? 0, windBearing: windiest?.windBearing
            )
        }

        // High and low over the calendar day, with times.
        let today = hoursIn(0..<24)
        let hot = today.max { $0.temperature < $1.temperature }
        let cold = today.min { $0.temperature < $1.temperature }

        let span = hoursIn(morning.lowerBound..<night.upperBound)
        let windows = wetWindows(span)
        let switchover = changeover(span)
        let snowTotal = span.reduce(0) { $0 + $1.snowfall }
        let rainTotal = span.reduce(0) { $0 + $1.rain }

        return DayPlan(
            date: day.date,
            parts: parts,
            windows: windows,
            high: hot?.temperature ?? day.high,
            highAt: hot?.time,
            low: cold?.temperature ?? day.low,
            lowAt: cold?.time,
            feelsLikeLow: span.map(\.feelsLike).min(),
            maxGust: span.compactMap(\.windGust).max(),
            rainTotal: hours.isEmpty ? day.rainInches : rainTotal,
            snowTotal: hours.isEmpty ? day.snowInches : snowTotal,
            sunrise: day.sunrise,
            sunset: day.sunset,
            changeover: changeoverText(switchover, timeZone: timeZone),
            summary: summary(parts: parts, windows: windows, changeover: switchover, rain: hours.isEmpty ? day.rainInches : rainTotal,
                             snow: hours.isEmpty ? day.snowInches : snowTotal, high: hot?.temperature ?? day.high,
                             highAt: hot?.time, chance: day.precipChance, hasHours: !hours.isEmpty, timeZone: timeZone)
        )
    }

    // MARK: - Pieces

    static func hourType(_ h: HourPoint) -> PrecipType {
        let snowLiquid = h.snowfall / IntensityRules.snowRatio
        if snowLiquid <= 0 && h.rain <= 0 { return h.precipitation > 0 ? .rain : .none }
        if snowLiquid > 0 && h.rain > 0 && min(snowLiquid, h.rain) / (snowLiquid + h.rain) >= 0.25 { return .mix }
        return snowLiquid >= h.rain ? .snow : .rain
    }

    static func wetWindows(_ hs: [HourPoint]) -> [DayPlan.WetWindow] {
        var windows: [DayPlan.WetWindow] = []
        var current: [HourPoint] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            var weight: [PrecipType: Double] = [:]
            for h in current { weight[hourType(h), default: 0] += max(h.precipitation, 0.001) }
            windows.append(DayPlan.WetWindow(
                start: first.time,
                end: last.time.addingTimeInterval(3600),
                type: NextHourAnalyzer.dominantType(weight),
                peak: current.max { $0.precipitation < $1.precipitation }!.time))
            current = []
        }
        for h in hs {
            if h.precipitation >= wetHour {
                // A single dry hour between wet ones doesn't split the window.
                if let last = current.last, h.time.timeIntervalSince(last.time) > 2 * 3600 { close() }
                current.append(h)
            }
        }
        close()
        return windows
    }

    struct Changeover { var from: PrecipType; var to: PrecipType; var at: Date }

    static func changeover(_ hs: [HourPoint]) -> Changeover? {
        let wet = hs.filter { $0.precipitation >= wetHour }.map { ($0.time, hourType($0)) }.filter { $0.1 == .rain || $0.1 == .snow }
        guard wet.count >= 4 else { return nil }
        for i in 1..<(wet.count - 1) where wet[i].1 != wet[i - 1].1 && wet[i + 1].1 == wet[i].1 {
            return Changeover(from: wet[i - 1].1, to: wet[i].1, at: wet[i].0)
        }
        return nil
    }

    static func changeoverText(_ c: Changeover?, timeZone: TimeZone) -> String? {
        c.map { "\($0.from.noun) turns to \($0.to.noun.lowercased()) ~\(Fmt.hour($0.at, timeZone: timeZone))" }
    }

    /// "snow 2–9 pm", or "rain from 10 am, turning to snow ~2 pm, ending ~7 pm".
    static func phrase(_ w: DayPlan.WetWindow, changeover c: Changeover?, timeZone: TimeZone) -> String {
        if let c, c.at > w.start, c.at < w.end {
            return "\(c.from.noun.lowercased()) from \(Fmt.hour(w.start, timeZone: timeZone)), turning to \(c.to.noun.lowercased()) ~\(Fmt.hour(c.at, timeZone: timeZone)), ending ~\(Fmt.hour(w.end, timeZone: timeZone))"
        }
        return "\(w.type.noun.lowercased()) \(Fmt.hourRange(w.start, w.end, timeZone: timeZone))"
    }

    static func symbol(rain: Double, snow: Double, cloud: Double?, night: Bool) -> DaySymbol {
        if snow >= 0.1 && rain >= 0.02 { return .mix }
        if snow >= 0.1 { return .snow }
        if rain >= 0.02 { return .rain }
        guard let cloud else { return .cloud }
        if cloud < 30 { return .sun }
        if cloud < 70 { return .partly }
        return .cloud
    }

    static func summary(parts: [DayPlan.Part], windows: [DayPlan.WetWindow], changeover: Changeover?, rain: Double, snow: Double,
                        high: Double, highAt: Date?, chance: Double, hasHours: Bool, timeZone: TimeZone) -> String {
        guard hasHours else {
            if snow >= 0.1 { return "\(Fmt.inchRange(snow)) of snow expected." }
            if rain >= 0.02 { return "Rain likely, about \(Fmt.inches(rain))." }
            return "Mostly dry. High \(Fmt.temp(high))."
        }
        guard let first = windows.first else {
            let peak = highAt.map { " around \(Fmt.hour($0, timeZone: timeZone))" } ?? ""
            let maybe = chance >= 0.3 ? " A stray shower can't be ruled out." : ""
            return "Dry all day. High \(Fmt.temp(high))\(peak).\(maybe)"
        }

        var lines: [String] = []
        let morningDry = parts.first { $0.name == .morning }?.isDry ?? false
        let firstPhrase = phrase(first, changeover: changeover, timeZone: timeZone)
        if morningDry, let morning = parts.first(where: { $0.name == .morning }), first.start >= morning.end {
            lines.append("Dry morning, then \(firstPhrase)")
        } else {
            lines.append(firstPhrase.prefix(1).uppercased() + firstPhrase.dropFirst())
        }
        if windows.count > 1 {
            let w = windows[1]
            lines[0] += ", and \(phrase(w, changeover: changeover, timeZone: timeZone)) later"
        }
        lines[0] += "."

        var totals: [String] = []
        if snow >= 0.1 { totals.append("\(Fmt.inchRange(snow)) of snow") }
        if rain >= 0.05 { totals.append("\(Fmt.inches(rain)) of rain") }
        if !totals.isEmpty {
            let heaviest = windows.max { a, b in
                a.end.timeIntervalSince(a.start) < b.end.timeIntervalSince(b.start)
            }!.peak
            lines.append(totals.joined(separator: " and ").prefix(1).uppercased()
                         + totals.joined(separator: " and ").dropFirst()
                         + ", heaviest around \(Fmt.hour(heaviest, timeZone: timeZone)).")
        }
        return lines.joined(separator: " ")
    }

    /// One line for Stowe days: what the upper mountain looks like.
    public static func skiVerdict(upperSnow: Double, upperRain: Double, windHold: WindHoldRisk?, windFrom: Date?, timeZone: TimeZone) -> String {
        var verdict: String
        if upperSnow >= 6 { verdict = "Big day up top: about \(Fmt.inchRange(upperSnow)) on the upper mountain." }
        else if upperSnow >= 2 { verdict = "Fresh snow up top: about \(Fmt.inchRange(upperSnow))." }
        else if upperRain >= 0.1 { verdict = "Rain up high. Groomers will be mashed potatoes." }
        else if upperSnow >= 0.5 { verdict = "A refresher up top, nothing deep." }
        else { verdict = "Groomer day. No real new snow up top." }
        if let windHold, windHold >= .elevated {
            verdict += " Wind holds possible\(windFrom.map { " after \(Fmt.hour($0, timeZone: timeZone))" } ?? "")."
        }
        return verdict
    }
}

extension Fmt {
    /// "2 pm"
    public static func hour(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "h a"
        return f.string(from: date).lowercased()
    }

    /// "2–9 pm", "10 am–2 pm"
    public static func hourRange(_ start: Date, _ end: Date, timeZone: TimeZone = .current) -> String {
        let a = hour(start, timeZone: timeZone), b = hour(end, timeZone: timeZone)
        let aParts = a.split(separator: " "), bParts = b.split(separator: " ")
        if aParts.count == 2, bParts.count == 2, aParts[1] == bParts[1] {
            return "\(aParts[0])–\(b)"
        }
        return "\(a)–\(b)"
    }
}
