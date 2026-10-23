import BackgroundTasks
import Foundation
import UpslopeCore
import WidgetKit

/// One place that refreshes everything: forecasts, alerts, Mansfield, the Stowe report,
/// widgets and the Live Activity. Runs in the foreground, in background refresh,
/// and on significant location changes.
actor Refresher {
    static let shared = Refresher()
    static var taskID: String { (Bundle.main.bundleIdentifier ?? "upslope") + ".refresh" }

    enum Reason: String { case foreground, background, moved, manual }

    static let minInterval: TimeInterval = 8 * 60
    static let reportInterval: TimeInterval = 30 * 60
    static let mountainInterval: TimeInterval = 30 * 60

    private var running = false

    static func scheduleBackground() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func run(reason: Reason, force: Bool = false) async {
        guard !running else { return }
        let now = Date()
        if !force, reason != .manual,
           let last = Store.load(Date.self, .lastRefresh), now.timeIntervalSince(last) < Self.minInterval {
            return
        }
        running = true
        defer { running = false }
        Store.save(now, .lastRefresh)
        var log = Store.load([String].self, "refreshLog") ?? []
        log.append("\(ISO8601DateFormatter().string(from: now)) \(reason.rawValue)")
        Store.save(Array(log.suffix(30)), "refreshLog")

        await LocationService.shared.refreshSavedLocation()
        let loader = ForecastLoader()
        async let here = try? loader.load(.here)
        async let stowe = try? loader.load(.stowe)
        let (h, _) = await (here, stowe)

        // Next-hour alert for wherever the phone is.
        if let h {
            var state = Store.load(AlertState.self, .alertState) ?? AlertState()
            let (action, newState) = AlertPlanner.plan(state: state, next: h.nextHourState, now: now, snark: Store.settings.snark)
            await Notifier.apply(action)
            state = newState
            Store.save(state, .alertState)
        }

        await refreshMountain(now: now, force: force)
        await refreshReport(now: now, force: force)

        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityManager.update(with: h)
    }

    private func refreshMountain(now: Date, force: Bool) async {
        let last = Store.load(MountainForecast.self, .mountain)?.fetchedAt ?? .distantPast
        guard force || now.timeIntervalSince(last) > Self.mountainInterval else { return }
        if let m = try? await MountainService().forecast(now: now) { Store.save(m, .mountain) }
        if let d = try? await NWSClient().latestDiscussion() { Store.save(d, .discussion) }
    }

    private func refreshReport(now: Date, force: Bool) async {
        let last = Store.load(Date.self, .lastReportFetch) ?? .distantPast
        guard force || now.timeIntervalSince(last) > Self.reportInterval else { return }
        Store.save(now, .lastReportFetch)
        guard let report = try? await StoweReportClient().fetch(now: now) else { return }
        Store.save(report, .report)

        let watch = Store.settings.watchList
        let previous = Store.load([String: Bool].self, .trailSnapshot) ?? [:]
        for name in TrailWatch.justOpened(previous: previous, report: report, watch: watch) {
            await Notifier.deliver(
                id: "upslope.trail.\(name).\(Int(now.timeIntervalSince1970))",
                title: "\(name) is open",
                body: Snark.trail(name, isOpen: true, level: Store.settings.snark, seed: Int(now.timeIntervalSince1970 / 86400)),
                thread: "trails")
        }
        Store.save(TrailWatch.snapshot(report, watch: watch), .trailSnapshot)
    }
}
