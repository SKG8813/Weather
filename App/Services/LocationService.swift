import CoreLocation
import Foundation
import UpslopeCore

/// One-shot fixes for "Here", plus significant-change monitoring so alerts follow you.
/// Main-actor bound because CLLocationManager wants the thread it was created on.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    /// iOS only shows this upgrade prompt after "While Using" has been granted.
    func requestAlways() { manager.requestAlwaysAuthorization() }

    func startMonitoringIfAllowed() {
        if manager.authorizationStatus == .authorizedAlways,
           CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    /// A fresh-enough fix, or nil if location isn't allowed.
    func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: break
        default: return nil
        }
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -300 { return last }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            if waiters.count == 1 { manager.requestLocation() }
        }
    }

    /// Updates the saved "Here" location and its place name.
    @discardableResult
    func refreshSavedLocation() async -> SavedLocation? {
        guard let loc = await currentLocation() else { return Store.load(SavedLocation.self, .lastLocation) }
        let saved = SavedLocation(
            coordinate: Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude),
            name: await placeName(for: loc) ?? "Here",
            at: loc.timestamp
        )
        Store.save(saved, .lastLocation)
        return saved
    }

    private func placeName(for loc: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(loc)
        guard let m = marks?.first else { return nil }
        let town = m.locality ?? m.subAdministrativeArea ?? m.name
        if let town, let state = m.administrativeArea { return "\(town), \(state)" }
        return town
    }

    // MARK: CLLocationManagerDelegate (called on the main thread)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.startMonitoringIfAllowed() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.deliver(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.deliver(nil) }
    }

    private func deliver(_ location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
        // Significant-change wakeups land here too, possibly with the app in the background.
        if pending.isEmpty, location != nil {
            Task { await Refresher.shared.run(reason: .moved) }
        }
    }
}
