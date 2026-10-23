import Foundation

public enum WindHoldRisk: Int, Codable, Sendable, Comparable {
    case low = 0, elevated, high
    public static func < (a: WindHoldRisk, b: WindHoldRisk) -> Bool { a.rawValue < b.rawValue }
    public var label: String {
        switch self {
        case .low: return "Low"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }
}

public enum UpslopeSignal: Int, Codable, Sendable, Comparable {
    case none = 0, moderate, strong
    public static func < (a: UpslopeSignal, b: UpslopeSignal) -> Bool { a.rawValue < b.rawValue }
    public var label: String {
        switch self {
        case .none: return "None"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        }
    }
}

public struct MountainForecast: Codable, Sendable, Equatable {
    public struct Spot: Codable, Sendable, Equatable {
        public var elevationFeet: Double
        public var current: Conditions?
        public var snow24h: Double
        public var rain24h: Double
    }

    public var fetchedAt: Date
    public var upper: Spot
    public var base: Spot
    /// Current snow line in feet (freezing level minus ~1,000′).
    public var snowLineFeet: Double?
    /// When, in the next 24 hours, the snow line first drops to the base.
    public var snowLineAtBaseBy: Date?
    public var upslope: UpslopeSignal
    public var upslopeStart: Date?
    public var windHold: WindHoldRisk
    public var windHoldFrom: Date?
    public var maxUpperGust: Double?
    /// Upper-mountain snowfall per day for 7 days.
    public var upperDailySnow: [DayAmount]

    public struct DayAmount: Codable, Sendable, Equatable {
        public var date: Date
        public var snow: Double
        public var rain: Double
    }

    public var weekSnowTotal: Double { upperDailySnow.reduce(0) { $0 + $1.snow } }
}

/// Mansfield heuristics from PLAN.md §3. These are our estimates, never the resort's.
public enum MountainRules {
    public static let snowLineBelowFreezingFeet = 1000.0
    public static let upslopeDirection = 270.0...340.0
    public static let upslopeMinWindMph = 15.0
    public static let upslopeMaxTempF = 32.0
    public static let upslopeMinHumidity = 80.0
    public static let windHoldElevatedMph = 40.0
    public static let windHoldHighMph = 50.0
    /// Lift hours, local time.
    public static let liftHours = 8...16

    public static func build(upper: OpenMeteoData, base: OpenMeteoData, now: Date) -> MountainForecast {
        let window = upper.hourlyTimes.indices.filter {
            let t = upper.hourlyTimes[$0]
            return t >= now.addingTimeInterval(-3600) && t < now.addingTimeInterval(24 * 3600)
        }

        func sum(_ d: OpenMeteoData, _ key: String) -> Double {
            d.hourlyTimes.indices
                .filter { d.hourlyTimes[$0] >= now && d.hourlyTimes[$0] < now.addingTimeInterval(24 * 3600) }
                .compactMap { d.hourlyValue(key, at: $0) }
                .reduce(0, +)
        }

        // Snow line.
        var snowLine: Double?
        var atBaseBy: Date?
        for i in window {
            guard let fl = upper.hourlyValue("freezing_level_height", at: i) else { continue }
            let line = max(0, fl - snowLineBelowFreezingFeet)
            if snowLine == nil { snowLine = line }
            if atBaseBy == nil, line <= Places.mansfieldBaseFeet { atBaseBy = upper.hourlyTimes[i] }
        }

        // Upslope: NW flow at ~5,000′, cold and moist.
        var upslopeHours = 0
        var upslopeStart: Date?
        for i in window {
            guard let dir = upper.hourlyValue("wind_direction_850hPa", at: i),
                  let spd = upper.hourlyValue("wind_speed_850hPa", at: i),
                  let tmp = upper.hourlyValue("temperature_850hPa", at: i),
                  let rh = upper.hourlyValue("relative_humidity_850hPa", at: i) else { continue }
            if upslopeDirection.contains(dir) && spd >= upslopeMinWindMph && tmp <= upslopeMaxTempF && rh >= upslopeMinHumidity {
                upslopeHours += 1
                if upslopeStart == nil { upslopeStart = upper.hourlyTimes[i] }
            }
        }
        let upslope: UpslopeSignal = upslopeHours >= 6 ? .strong : (upslopeHours >= 2 ? .moderate : .none)

        // Wind hold: upper gusts during lift hours.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = upper.timeZone
        var maxGust: Double?
        var holdFrom: Date?
        for i in window {
            let t = upper.hourlyTimes[i]
            guard liftHours.contains(cal.component(.hour, from: t)),
                  let g = upper.hourlyValue("wind_gusts_10m", at: i) else { continue }
            maxGust = max(maxGust ?? 0, g)
            if holdFrom == nil, g >= windHoldElevatedMph { holdFrom = t }
        }
        let hold: WindHoldRisk = (maxGust ?? 0) >= windHoldHighMph ? .high : ((maxGust ?? 0) >= windHoldElevatedMph ? .elevated : .low)

        let daily = upper.days.map { MountainForecast.DayAmount(date: $0.date, snow: $0.snowInches, rain: $0.rainInches) }

        return MountainForecast(
            fetchedAt: now,
            upper: .init(elevationFeet: Places.mansfieldUpperFeet, current: upper.current, snow24h: sum(upper, "snowfall"), rain24h: sum(upper, "rain")),
            base: .init(elevationFeet: Places.mansfieldBaseFeet, current: base.current, snow24h: sum(base, "snowfall"), rain24h: sum(base, "rain")),
            snowLineFeet: snowLine,
            snowLineAtBaseBy: atBaseBy,
            upslope: upslope,
            upslopeStart: upslopeStart,
            windHold: hold,
            windHoldFrom: holdFrom,
            maxUpperGust: maxGust,
            upperDailySnow: daily
        )
    }
}

public struct MountainService: Sendable {
    public var openMeteo: OpenMeteoClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        openMeteo = OpenMeteoClient(http: http)
    }

    public func forecast(now: Date = Date()) async throws -> MountainForecast {
        async let u = openMeteo.fetch(Places.mansfieldUpper, elevationFeet: Places.mansfieldUpperFeet)
        async let b = openMeteo.fetch(Places.mansfieldBase, elevationFeet: Places.mansfieldBaseFeet)
        return try await MountainRules.build(upper: u, base: b, now: now)
    }
}
