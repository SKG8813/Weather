import ActivityKit
import Foundation
import UpslopeCore

/// "Track this storm". May be unavailable with a free Apple ID; Diagnostics reports why.
enum LiveActivityManager {
    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    static var isRunning: Bool { !Activity<StormAttributes>.activities.isEmpty }

    static func contentState(for forecast: Forecast, now: Date = Date()) -> StormAttributes.ContentState? {
        let state = forecast.nextHour.map { NextHourAnalyzer.analyze($0, now: now) } ?? .dry
        guard let e = state.event else { return nil }
        let bars = NextHourBars.bars(forecast.nextHour, now: now)
        return StormAttributes.ContentState(
            typeName: e.type.noun,
            start: e.start,
            end: e.end,
            continuesPastWindow: e.continuesPastWindow,
            peakRate: e.peakRate,
            peakTime: e.peakTime,
            total: e.displayTotal,
            bars: bars.map(\.level),
            barsFrom: now,
            heavyFromLevel: 1.0,
            snark: Snark.line(for: state, level: Store.settings.snark)
        )
    }

    /// Starts tracking the event in this forecast. Throws ActivityKit's error if it can't.
    static func start(for forecast: Forecast) throws {
        guard let state = contentState(for: forecast) else { return }
        for a in Activity<StormAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        _ = try Activity.request(
            attributes: StormAttributes(placeName: forecast.placeName),
            content: ActivityContent(state: state, staleDate: state.end.addingTimeInterval(15 * 60)),
            pushType: nil
        )
    }

    /// Keeps running activities in sync; ends them once it's dry.
    static func update(with forecast: Forecast?) async {
        for a in Activity<StormAttributes>.activities {
            if let f = forecast, let state = contentState(for: f) {
                await a.update(ActivityContent(state: state, staleDate: state.end.addingTimeInterval(15 * 60)))
            } else {
                await a.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(10 * 60)))
            }
        }
    }

    /// For Diagnostics: a 10-minute fake event so you can see the card.
    static func startTest() throws {
        let now = Date()
        let start = now.addingTimeInterval(120)
        let levels = (0..<60).map { i -> Double in (2..<12).contains(i) ? 0.4 + Double(i % 5) * 0.2 : 0 }
        let state = StormAttributes.ContentState(
            typeName: "Snow", start: start, end: start.addingTimeInterval(600), continuesPastWindow: false,
            peakRate: 1.1, peakTime: start.addingTimeInterval(300), total: 0.2, bars: levels, barsFrom: now,
            heavyFromLevel: 1.0, snark: "Test storm. If you can read this, Live Activities work.")
        _ = try Activity.request(attributes: StormAttributes(placeName: "Test"),
                                 content: ActivityContent(state: state, staleDate: start.addingTimeInterval(900)),
                                 pushType: nil)
    }

    static func endAll() async {
        for a in Activity<StormAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
