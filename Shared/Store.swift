import Foundation
import UpslopeCore

enum PlaceChoice: String, Codable, CaseIterable, Identifiable {
    case here, stowe
    var id: String { rawValue }
    var label: String { self == .here ? "Here" : "Stowe" }
}

struct UserSettings: Codable, Equatable {
    var snark: SnarkLevel = .standard
    var watchList: [String] = TrailWatch.defaultWatchList
}

struct SavedLocation: Codable, Equatable {
    var coordinate: Coordinate
    var name: String
    var at: Date
}

/// Build-time values from Info.plist (filled from Config/Local.xcconfig).
enum AppConfig {
    static var pirateKey: String? {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "PirateWeatherKey") as? String,
              !k.isEmpty, !k.hasPrefix("$(") else { return nil }
        return k
    }

    static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    /// False when the App Group entitlement didn't make it into the signed build.
    static var appGroupAvailable: Bool {
        guard let id = appGroupID else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
    }
}

/// Small Codable store shared by the app and widgets (via the App Group when available).
enum Store {
    static var defaults: UserDefaults {
        if AppConfig.appGroupAvailable, let id = AppConfig.appGroupID, let d = UserDefaults(suiteName: id) { return d }
        return .standard
    }

    enum Key: String {
        case settings, alertState, trailSnapshot, lastLocation, mountain, report, discussion
        case lastRefresh, lastReportFetch
    }

    static func forecastKey(_ place: PlaceChoice) -> String { "forecast.\(place.rawValue)" }

    static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T?, _ key: String) {
        guard let value else { defaults.removeObject(forKey: key); return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        if let data = try? e.encode(value) { defaults.set(data, forKey: key) }
    }

    static func load<T: Decodable>(_ type: T.Type, _ key: Key) -> T? { load(type, key.rawValue) }
    static func save<T: Encodable>(_ value: T?, _ key: Key) { save(value, key.rawValue) }

    static var settings: UserSettings {
        get { load(UserSettings.self, .settings) ?? UserSettings() }
        set { save(newValue, .settings) }
    }
}

extension Forecast {
    var nextHourState: NextHourState {
        nextHour.map { NextHourAnalyzer.analyze($0, now: Date()) } ?? .dry
    }
}
