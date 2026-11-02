import Foundation

/// Decides when a Pirate Weather call is worth it. Open-Meteo is checked first
/// (free, generous limits); Pirate Weather's minute-by-minute data is only fetched
/// when rain or snow is possible soon, which keeps a free key's monthly calls low.
public enum PirateGate {
    /// How far ahead to look for possible precipitation.
    public static let lookaheadHours = 2.0
    /// Hourly probability (percent) that counts as "possible".
    public static let minProbability = 20.0

    public static func wetPossible(_ o: OpenMeteoData, now: Date) -> Bool {
        let end = now.addingTimeInterval(lookaheadHours * 3600)

        let precip15 = o.minutely["precipitation"] ?? []
        for (i, t) in o.minutelyTimes.enumerated() where t > now && t <= end.addingTimeInterval(15 * 60) {
            if i < precip15.count, (precip15[i] ?? 0) > 0 { return true }
        }

        for (i, t) in o.hourlyTimes.enumerated() where t > now.addingTimeInterval(-3600) && t <= end {
            if (o.hourlyValue("precipitation", at: i) ?? 0) > 0 { return true }
            if (o.hourlyValue("precipitation_probability", at: i) ?? 0) >= minProbability { return true }
        }
        return false
    }
}

/// Combines Open-Meteo (7-day, current, dry-weather next hour) with Pirate Weather
/// (minute-by-minute next hour, only when it might rain or snow).
public struct ForecastService: Sendable {
    public var pirate: PirateWeatherClient?
    public var openMeteo: OpenMeteoClient

    public init(pirateKey: String?, http: HTTPClient = URLSessionHTTPClient()) {
        if let key = pirateKey, !key.isEmpty, !key.hasPrefix("$(") {
            pirate = PirateWeatherClient(apiKey: key, http: http)
        }
        openMeteo = OpenMeteoClient(http: http)
    }

    public func forecast(placeName: String, at c: Coordinate, now: Date = Date()) async throws -> Forecast {
        let o = try? await openMeteo.fetch(c)

        // Only spend a Pirate Weather call when Open-Meteo sees something coming, or is down.
        var p: PirateWeatherClient.Result?
        if let pirate, o.map({ PirateGate.wetPossible($0, now: now) }) ?? true {
            p = try? await pirate.fetch(c)
        }
        guard p != nil || o != nil else { throw HTTPError.badResponse }

        var nextHour = p?.nextHour
        var source: ForecastSource? = nextHour == nil ? nil : .pirateWeather
        if nextHour == nil, let backup = o?.nextHour {
            nextHour = backup
            source = .openMeteo
        }
        let days = o.map(\.days).flatMap { $0.isEmpty ? nil : $0 } ?? p?.days ?? []
        return Forecast(
            placeName: placeName,
            coordinate: c,
            fetchedAt: now,
            current: p?.current ?? o?.current,
            nextHour: nextHour,
            nextHourSource: source,
            days: Array(days.prefix(7))
        )
    }
}
