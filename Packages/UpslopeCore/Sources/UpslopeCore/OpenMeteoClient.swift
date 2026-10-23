import Foundation

/// Open-Meteo: no key. Used for the 7-day forecast, Mansfield elevation forecasts,
/// and as the backup next-hour source (15-minute steps).
public struct OpenMeteoClient: Sendable {
    public var http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    static let hourlyFields = [
        "temperature_2m", "apparent_temperature", "precipitation", "rain", "snowfall",
        "precipitation_probability", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m",
        "freezing_level_height", "wind_speed_850hPa", "wind_direction_850hPa",
        "temperature_850hPa", "relative_humidity_850hPa"
    ]
    static let dailyFields = [
        "weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_probability_max",
        "rain_sum", "showers_sum", "snowfall_sum", "precipitation_sum"
    ]
    static let currentFields = [
        "temperature_2m", "apparent_temperature", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m"
    ]
    static let minutelyFields = ["precipitation", "rain", "snowfall"]

    public func url(for c: Coordinate, elevationFeet: Double? = nil) -> URL {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var q = [
            URLQueryItem(name: "latitude", value: String(c.latitude)),
            URLQueryItem(name: "longitude", value: String(c.longitude)),
            URLQueryItem(name: "current", value: Self.currentFields.joined(separator: ",")),
            URLQueryItem(name: "minutely_15", value: Self.minutelyFields.joined(separator: ",")),
            URLQueryItem(name: "forecast_minutely_15", value: "8"),
            URLQueryItem(name: "hourly", value: Self.hourlyFields.joined(separator: ",")),
            URLQueryItem(name: "daily", value: Self.dailyFields.joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        if let ft = elevationFeet {
            q.append(URLQueryItem(name: "elevation", value: String(Int((ft * 0.3048).rounded()))))
        }
        comps.queryItems = q
        return comps.url!
    }

    public func fetch(_ c: Coordinate, elevationFeet: Double? = nil) async throws -> OpenMeteoData {
        let data = try await http.get(url(for: c, elevationFeet: elevationFeet), headers: ["User-Agent": UserAgent.value])
        return try OpenMeteoData(json: data)
    }
}

/// Columns from an Open-Meteo response, normalized to °F, mph, inches and feet.
public struct OpenMeteoData: Sendable {
    public var timeZone: TimeZone
    public var current: Conditions?
    public var hourlyTimes: [Date]
    public var hourly: [String: [Double?]]
    public var dailyTimes: [Date]
    public var daily: [String: [Double?]]
    public var minutelyTimes: [Date]
    public var minutely: [String: [Double?]]

    public init(json data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPError.badResponse
        }
        let offset = (root["utc_offset_seconds"] as? NSNumber)?.intValue ?? 0
        timeZone = (root["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: offset) ?? .current

        func section(_ name: String) -> ([Date], [String: [Double?]]) {
            guard let s = root[name] as? [String: Any] else { return ([], [:]) }
            let units = root["\(name)_units"] as? [String: String] ?? [:]
            let times = (s["time"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }.map { Date(timeIntervalSince1970: $0) }
            var cols: [String: [Double?]] = [:]
            for (k, v) in s where k != "time" {
                guard let arr = v as? [Any] else { continue }
                cols[k] = arr.map { ($0 as? NSNumber)?.doubleValue }.map { Self.normalize($0, unit: units[k]) }
            }
            return (times, cols)
        }

        (hourlyTimes, hourly) = section("hourly")
        (dailyTimes, daily) = section("daily")
        (minutelyTimes, minutely) = section("minutely_15")

        if let c = root["current"] as? [String: Any] {
            let units = root["current_units"] as? [String: String] ?? [:]
            func v(_ k: String) -> Double? { Self.normalize((c[k] as? NSNumber)?.doubleValue, unit: units[k]) }
            if let t = v("temperature_2m") {
                current = Conditions(temperature: t, feelsLike: v("apparent_temperature") ?? t, windSpeed: v("wind_speed_10m") ?? 0, windGust: v("wind_gusts_10m"), windBearing: v("wind_direction_10m"))
            }
        }
    }

    /// Convert anything metric that slipped through into our units.
    static func normalize(_ value: Double?, unit: String?) -> Double? {
        guard let v = value else { return nil }
        switch unit {
        case "°C": return v * 9 / 5 + 32
        case "km/h": return v * 0.621371
        case "m/s": return v * 2.23694
        case "mm": return v / 25.4
        case "cm": return v / 2.54
        case "m": return v * 3.28084
        default: return v
        }
    }

    public func hourlyValue(_ key: String, at i: Int) -> Double? {
        guard let col = hourly[key], i < col.count else { return nil }
        return col[i]
    }

    /// Next-hour precipitation from 15-minute data. Values are sums over the preceding 15 minutes.
    public var nextHour: NextHour? {
        guard !minutelyTimes.isEmpty else { return nil }
        let precip = minutely["precipitation"] ?? []
        let rain = minutely["rain"] ?? []
        let snow = minutely["snowfall"] ?? []
        var points: [MinutePoint] = []
        for (i, t) in minutelyTimes.enumerated() {
            let p = (i < precip.count ? precip[i] : nil) ?? 0
            let r = (i < rain.count ? rain[i] : nil) ?? 0
            let s = (i < snow.count ? snow[i] : nil) ?? 0
            let type: PrecipType
            if p <= 0 { type = .none }
            else if s > 0 && r > 0 { type = .mix }
            else if s > 0 { type = .snow }
            else { type = .rain }
            // Model output has no probability; treat wet steps as likely.
            points.append(MinutePoint(time: t.addingTimeInterval(-15 * 60), rate: p * 4, probability: p > 0 ? 0.8 : 0, type: type))
        }
        return NextHour(points: points, stepMinutes: 15)
    }

    public var days: [DayForecast] {
        dailyTimes.enumerated().compactMap { i, t in
            func v(_ k: String) -> Double? {
                guard let col = daily[k], i < col.count else { return nil }
                return col[i]
            }
            guard let hi = v("temperature_2m_max"), let lo = v("temperature_2m_min") else { return nil }
            let rain = (v("rain_sum") ?? 0) + (v("showers_sum") ?? 0)
            let snow = v("snowfall_sum") ?? 0
            return DayForecast(
                date: t, high: hi, low: lo,
                precipChance: (v("precipitation_probability_max") ?? 0) / 100,
                rainInches: rain, snowInches: snow,
                symbol: Self.symbol(code: v("weather_code").map { Int($0) }, rain: rain, snow: snow)
            )
        }
    }

    /// WMO weather codes → our icons.
    static func symbol(code: Int?, rain: Double, snow: Double) -> DaySymbol {
        switch code {
        case 0, 1: return .sun
        case 2: return .partly
        case 3: return .cloud
        case 45, 48: return .fog
        case 56, 57, 66, 67: return .mix
        case 51, 53, 55, 61, 63, 65, 80, 81, 82: return snow > 0.5 && rain > 0.05 ? .mix : .rain
        case 71, 73, 75, 77, 85, 86: return rain > 0.1 && snow > 0 ? .mix : .snow
        case 95, 96, 99: return .storm
        default: return .cloud
        }
    }
}
