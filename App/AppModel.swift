import Foundation
import Observation
import UpslopeCore

/// What the screens show. Data comes from the shared Store, which Refresher fills.
@MainActor
@Observable
final class AppModel {
    var place: PlaceChoice = .here
    var forecasts: [PlaceChoice: Forecast] = [:]
    var mountain: MountainForecast?
    var report: ResortReport?
    var discussion: ForecastDiscussion?
    var settings = Store.settings
    var isRefreshing = false
    /// Ticks once a minute so countdowns re-render.
    var now = Date()

    private var ticker: Task<Void, Never>?

    init() {
        reloadFromStore()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.now = Date()
            }
        }
    }

    var forecast: Forecast? { forecasts[place] }
    var nextHour: NextHourState {
        forecast?.nextHour.map { NextHourAnalyzer.analyze($0, now: now) } ?? .dry
    }

    func reloadFromStore() {
        for p in PlaceChoice.allCases { forecasts[p] = ForecastLoader.cached(p) }
        mountain = Store.load(MountainForecast.self, .mountain)
        report = Store.load(ResortReport.self, .report)
        discussion = Store.load(ForecastDiscussion.self, .discussion)
        settings = Store.settings
        now = Date()
    }

    func refresh(force: Bool = false) async {
        if LocationService.shared.authorization == .notDetermined { LocationService.shared.requestWhenInUse() }
        if await Notifier.status() == .notDetermined { await Notifier.requestPermission() }
        isRefreshing = true
        await Refresher.shared.run(reason: force ? .manual : .foreground, force: force)
        reloadFromStore()
        isRefreshing = false
    }

    func updateSettings(_ change: (inout UserSettings) -> Void) {
        var s = settings
        change(&s)
        settings = s
        Store.settings = s
    }
}
