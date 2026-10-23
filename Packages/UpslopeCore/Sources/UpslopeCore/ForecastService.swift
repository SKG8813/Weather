import Foundation

/// Combines Pirate Weather (next hour, current) with Open-Meteo (7-day, backup).
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
        async let pw: PirateWeatherClient.Result? = { try? await pirate?.fetch(c) }()
        async let om: OpenMeteoData? = { try? await openMeteo.fetch(c) }()
        let (p, o) = await (pw, om)
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
