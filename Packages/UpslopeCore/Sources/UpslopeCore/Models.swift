import Foundation

/// What is falling.
public enum PrecipType: String, Codable, Sendable, CaseIterable {
    case none, rain, snow, mix

    public var noun: String {
        switch self {
        case .none: return "Nothing"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .mix: return "Mix"
        }
    }
}

/// Our intensity scale, shown with trail-sign shapes in the UI.
public enum Intensity: Int, Codable, Sendable, Comparable {
    case none = 0, light, moderate, heavy

    public static func < (lhs: Intensity, rhs: Intensity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }
}

public struct Coordinate: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One step of the next-hour forecast. `rate` is liquid-equivalent inches per hour.
public struct MinutePoint: Codable, Sendable, Equatable {
    public var time: Date
    public var rate: Double
    public var probability: Double
    public var type: PrecipType

    public init(time: Date, rate: Double, probability: Double, type: PrecipType) {
        self.time = time
        self.rate = rate
        self.probability = probability
        self.type = type
    }
}

/// Minute-by-minute (or 15-minute) precipitation for roughly the next hour.
public struct NextHour: Codable, Sendable, Equatable {
    public var points: [MinutePoint]
    /// Spacing between points, in minutes (1 for Pirate Weather, 15 for Open-Meteo).
    public var stepMinutes: Int

    public init(points: [MinutePoint], stepMinutes: Int) {
        self.points = points
        self.stepMinutes = stepMinutes
    }
}

public struct Conditions: Codable, Sendable, Equatable {
    public var temperature: Double
    public var feelsLike: Double
    public var windSpeed: Double
    public var windGust: Double?
    /// Degrees the wind is coming from.
    public var windBearing: Double?

    public init(temperature: Double, feelsLike: Double, windSpeed: Double, windGust: Double? = nil, windBearing: Double? = nil) {
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windBearing = windBearing
    }
}

public enum DaySymbol: String, Codable, Sendable {
    case sun, partly, cloud, rain, snow, mix, fog, storm
}

public struct DayForecast: Codable, Sendable, Equatable {
    public var date: Date
    public var high: Double
    public var low: Double
    /// 0...1
    public var precipChance: Double
    public var rainInches: Double
    public var snowInches: Double
    public var symbol: DaySymbol
    public var sunrise: Date?
    public var sunset: Date?

    public init(date: Date, high: Double, low: Double, precipChance: Double, rainInches: Double, snowInches: Double, symbol: DaySymbol,
                sunrise: Date? = nil, sunset: Date? = nil) {
        self.date = date
        self.high = high
        self.low = low
        self.precipChance = precipChance
        self.rainInches = rainInches
        self.snowInches = snowInches
        self.symbol = symbol
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// One hour of the 7-day forecast. Never shown as a list; used to summarize a day.
public struct HourPoint: Codable, Sendable, Equatable {
    public var time: Date
    public var temperature: Double
    public var feelsLike: Double
    /// Liquid-equivalent inches in this hour.
    public var precipitation: Double
    public var rain: Double
    /// Inches of snow (not liquid) in this hour.
    public var snowfall: Double
    /// 0...1
    public var probability: Double
    public var windSpeed: Double
    public var windGust: Double?
    public var windBearing: Double?
    /// 0...100
    public var cloudCover: Double?

    public init(time: Date, temperature: Double, feelsLike: Double, precipitation: Double, rain: Double, snowfall: Double,
                probability: Double, windSpeed: Double, windGust: Double? = nil, windBearing: Double? = nil, cloudCover: Double? = nil) {
        self.time = time
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.precipitation = precipitation
        self.rain = rain
        self.snowfall = snowfall
        self.probability = probability
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windBearing = windBearing
        self.cloudCover = cloudCover
    }
}

public enum ForecastSource: String, Codable, Sendable {
    case pirateWeather, openMeteo
}

public struct Forecast: Codable, Sendable, Equatable {
    public var placeName: String
    public var coordinate: Coordinate
    public var fetchedAt: Date
    public var current: Conditions?
    public var nextHour: NextHour?
    public var nextHourSource: ForecastSource?
    public var days: [DayForecast]
    /// Hourly data behind the day plans. Optional so older saved forecasts still load.
    public var hours: [HourPoint]?
    public var timeZoneID: String?

    public init(placeName: String, coordinate: Coordinate, fetchedAt: Date, current: Conditions?, nextHour: NextHour?, nextHourSource: ForecastSource?, days: [DayForecast],
                hours: [HourPoint]? = nil, timeZoneID: String? = nil) {
        self.placeName = placeName
        self.coordinate = coordinate
        self.fetchedAt = fetchedAt
        self.current = current
        self.nextHour = nextHour
        self.nextHourSource = nextHourSource
        self.days = days
        self.hours = hours
        self.timeZoneID = timeZoneID
    }

    public var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// Older than this and the UI shows "as of …".
    public func isStale(now: Date, after minutes: Double = 45) -> Bool {
        now.timeIntervalSince(fetchedAt) > minutes * 60
    }
}

public enum Places {
    /// Stowe village.
    public static let stowe = Coordinate(latitude: 44.4654, longitude: -72.6874)
    /// Upper Mansfield ski terrain, around the top of the gondola. Approximate.
    public static let mansfieldUpper = Coordinate(latitude: 44.5350, longitude: -72.7960)
    /// Mansfield base area. Approximate.
    public static let mansfieldBase = Coordinate(latitude: 44.5310, longitude: -72.7850)
    /// Elevations in feet used for the Open-Meteo `elevation` downscaling.
    public static let mansfieldUpperFeet = 3600.0
    public static let mansfieldBaseFeet = 1560.0
}
