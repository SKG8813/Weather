import CoreLocation
import Foundation
import UpslopeCore

/// Fetches a forecast for a place choice. Used by both the app and the widgets,
/// so a widget can refresh itself even if the app hasn't run in a while.
struct ForecastLoader {
    var service = ForecastService(pirateKey: AppConfig.pirateKey)

    /// Where "Here" is: the freshest of the system's last fix and what the app saved.
    static func hereLocation() -> SavedLocation? {
        let saved = Store.load(SavedLocation.self, .lastLocation)
        let manager = CLLocationManager()
        if let fix = manager.location, fix.timestamp > (saved?.at ?? .distantPast) {
            let c = Coordinate(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
            // Keep the saved name if we haven't moved far; the app re-geocodes when it runs.
            let near = saved.map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: fix) < 3000 } ?? false
            return SavedLocation(coordinate: c, name: near ? saved!.name : "Here", at: fix.timestamp)
        }
        return saved
    }

    func load(_ place: PlaceChoice) async throws -> Forecast {
        let forecast: Forecast
        switch place {
        case .stowe:
            forecast = try await service.forecast(placeName: "Stowe, VT", at: Places.stowe)
        case .here:
            let loc = Self.hereLocation() ?? SavedLocation(coordinate: Places.stowe, name: "Stowe, VT", at: Date())
            forecast = try await service.forecast(placeName: loc.name, at: loc.coordinate)
        }
        Store.save(forecast, Store.forecastKey(place))
        return forecast
    }

    static func cached(_ place: PlaceChoice) -> Forecast? {
        Store.load(Forecast.self, Store.forecastKey(place))
    }
}
