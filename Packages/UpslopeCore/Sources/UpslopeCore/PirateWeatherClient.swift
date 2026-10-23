import Foundation

/// Pirate Weather (Dark Sky–compatible). Primary source for minute-by-minute precipitation.
public struct PirateWeatherClient: Sendable {
    public var apiKey: String
    public var http: HTTPClient

    public init(apiKey: String, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public struct Result: Sendable {
        public var current: Conditions?
        public var nextHour: NextHour?
        public var days: [DayForecast]
    }

    public func url(for c: Coordinate) -> URL {
        var comps = URLComponents(string: "https://api.pirateweather.net/forecast/\(apiKey)/\(c.latitude),\(c.longitude)")!
        comps.queryItems = [
            URLQueryItem(name: "units", value: "us"),
            URLQueryItem(name: "exclude", value: "hourly,alerts,flags")
        ]
        return comps.url!
    }

    public func fetch(_ c: Coordinate) async throws -> Result {
        guard !apiKey.isEmpty else { throw HTTPError.missingKey }
        let data = try await http.get(url(for: c), headers: ["User-Agent": UserAgent.value])
        return try Self.parse(data)
    }

    // MARK: - Parsing

    struct Response: Decodable {
        struct Currently: Decodable {
            var temperature: Double?
            var apparentTemperature: Double?
            var windSpeed: Double?
            var windGust: Double?
            var windBearing: Double?
        }
        struct Minute: Decodable {
            var time: Double
            var precipIntensity: Double?
            var precipProbability: Double?
            var precipType: String?
        }
        struct Day: Decodable {
            var time: Double
            var icon: String?
            var temperatureHigh: Double?
            var temperatureLow: Double?
            var precipProbability: Double?
            var precipAccumulation: Double?
            var precipType: String?
        }
        struct Block<T: Decodable>: Decodable { var data: [T] }

        var currently: Currently?
        var minutely: Block<Minute>?
        var daily: Block<Day>?
    }

    public static func parse(_ data: Data) throws -> Result {
        let r = try JSONDecoder().decode(Response.self, from: data)

        let current = r.currently.flatMap { c -> Conditions? in
            guard let t = c.temperature else { return nil }
            return Conditions(temperature: t, feelsLike: c.apparentTemperature ?? t, windSpeed: c.windSpeed ?? 0, windGust: c.windGust, windBearing: c.windBearing)
        }

        let points = (r.minutely?.data ?? []).map { m in
            MinutePoint(
                time: Date(timeIntervalSince1970: m.time),
                rate: max(0, m.precipIntensity ?? 0),
                probability: m.precipProbability ?? 0,
                type: precipType(m.precipType, rate: m.precipIntensity ?? 0)
            )
        }
        let nextHour = points.isEmpty ? nil : NextHour(points: points, stepMinutes: 1)

        let days = (r.daily?.data ?? []).compactMap { d -> DayForecast? in
            guard let hi = d.temperatureHigh, let lo = d.temperatureLow else { return nil }
            let type = precipType(d.precipType, rate: 1)
            let acc = d.precipAccumulation ?? 0
            return DayForecast(
                date: Date(timeIntervalSince1970: d.time),
                high: hi, low: lo,
                precipChance: d.precipProbability ?? 0,
                rainInches: type == .snow ? 0 : acc,
                snowInches: type == .snow ? acc : 0,
                symbol: symbol(d.icon)
            )
        }
        return Result(current: current, nextHour: nextHour, days: days)
    }

    static func precipType(_ s: String?, rate: Double) -> PrecipType {
        guard rate > 0 else { return .none }
        switch s?.lowercased() {
        case "snow": return .snow
        case "sleet", "ice", "mixed": return .mix
        case "rain": return .rain
        default: return .rain
        }
    }

    static func symbol(_ icon: String?) -> DaySymbol {
        switch icon {
        case "clear-day", "clear-night": return .sun
        case "partly-cloudy-day", "partly-cloudy-night": return .partly
        case "rain": return .rain
        case "snow": return .snow
        case "sleet": return .mix
        case "fog": return .fog
        default: return .cloud
        }
    }
}
