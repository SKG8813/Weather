import ActivityKit
import SwiftUI
import UpslopeCore
import WidgetKit

/// Phase 0: checks what a free Apple ID allows on this phone and whether each data source answers.
struct DiagnosticsView: View {
    enum Status { case pending, ok, warn, fail }

    struct Check: Identifiable {
        let id: String
        var title: String
        var status: Status = .pending
        var detail = ""
    }

    @State private var checks: [Check] = [
        Check(id: "notify", title: "Silent notifications"),
        Check(id: "location", title: "Location"),
        Check(id: "bg", title: "Background App Refresh"),
        Check(id: "group", title: "App Group (app ↔ widget sharing)"),
        Check(id: "widgets", title: "Widgets installed"),
        Check(id: "live", title: "Live Activities"),
        Check(id: "pirate", title: "Pirate Weather"),
        Check(id: "openmeteo", title: "Open-Meteo"),
        Check(id: "nws", title: "NWS Burlington discussion"),
        Check(id: "stowe", title: "stowe.com terrain report"),
        Check(id: "refresh", title: "Background runs so far")
    ]
    @State private var running = false
    @State private var stoweHTMLFile: URL?

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run all checks") { Task { await runAll() } }
                    .disabled(running)
            } footer: {
                Text("Run this once after installing, then screenshot it for Claude.")
            }

            Section("Results") {
                ForEach(checks) { c in
                    HStack(alignment: .top, spacing: 10) {
                        icon(c.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(UFont.body(16, weight: .semibold))
                            if !c.detail.isEmpty {
                                Text(c.detail).font(UFont.body(13)).foregroundStyle(Theme.muted).textSelection(.enabled)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Try it") {
                Button("Send a test silent alert") {
                    Task {
                        await Notifier.requestPermission()
                        await Notifier.deliver(id: "upslope.test", title: "Snow in 12 min · ~40 min · up to 1.1″/hr",
                                               body: "Test alert. No sound, as promised.", thread: "test")
                    }
                }
                Button("Start a test Live Activity") {
                    do {
                        try LiveActivityManager.startTest()
                        set("live", .ok, "Test activity started. Lock the phone to see it.")
                    } catch {
                        set("live", .fail, "Couldn't start: \(error.localizedDescription)")
                    }
                }
                Button("End Live Activities") { Task { await LiveActivityManager.endAll() } }
                Button("Reload widgets") { WidgetCenter.shared.reloadAllTimelines() }
                if let stoweHTMLFile {
                    ShareLink("Share the stowe.com page Upslope saw", item: stoweHTMLFile)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Diagnostics")
        .task { await runAll() }
    }

    @ViewBuilder func icon(_ s: Status) -> some View {
        switch s {
        case .pending: Image(systemName: "circle.dotted").foregroundStyle(Theme.muted)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.trailGreen)
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
        case .fail: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    func set(_ id: String, _ s: Status, _ detail: String) {
        if let i = checks.firstIndex(where: { $0.id == id }) {
            checks[i].status = s
            checks[i].detail = detail
        }
    }

    func runAll() async {
        running = true
        defer { running = false }

        switch await Notifier.status() {
        case .authorized, .provisional, .ephemeral: set("notify", .ok, "Allowed. Upslope never requests sound.")
        case .denied: set("notify", .fail, "Turned off in iPhone Settings › Notifications › Upslope.")
        default: set("notify", .warn, "Not asked yet. Tap \"Send a test silent alert\".")
        }

        switch LocationService.shared.authorization {
        case .authorizedAlways: set("location", .ok, "Always. Alerts can follow you.")
        case .authorizedWhenInUse: set("location", .warn, "While using only. Settings tab › Allow \"Always\" so alerts follow you.")
        case .denied, .restricted: set("location", .fail, "Off. \"Here\" will fall back to Stowe.")
        default: set("location", .warn, "Not asked yet.")
        }

        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: set("bg", .ok, "On.")
        case .denied: set("bg", .fail, "Off in iPhone Settings › General › Background App Refresh.")
        default: set("bg", .fail, "Restricted (Low Power Mode?).")
        }

        set("group", AppConfig.appGroupAvailable ? .ok : .warn,
            AppConfig.appGroupAvailable ? "\(AppConfig.appGroupID ?? "") is working."
                : "Not available with this signing. Widgets still work but fetch on their own.")

        if let configs = try? await WidgetCenter.shared.currentConfigurations() {
            set("widgets", configs.isEmpty ? .warn : .ok,
                configs.isEmpty ? "None yet. Long-press the lock screen › Customize › add Upslope."
                    : configs.map { "\($0.family)" }.joined(separator: ", "))
        }

        let live = ActivityAuthorizationInfo()
        set("live", live.areActivitiesEnabled ? .ok : .warn,
            live.areActivitiesEnabled ? "Enabled. Tap \"Start a test Live Activity\" to confirm."
                : "Disabled for Upslope (iPhone Settings › Upslope › Live Activities), or not allowed with this signing.")

        if let key = AppConfig.pirateKey {
            do {
                let r = try await PirateWeatherClient(apiKey: key).fetch(Places.stowe)
                set("pirate", .ok, "\(r.nextHour?.points.count ?? 0) minutes of data for Stowe.")
            } catch {
                set("pirate", .fail, "\(error)")
            }
        } else {
            set("pirate", .warn, "No key in Config/Local.xcconfig. Using Open-Meteo's 15-minute data.")
        }

        do {
            let d = try await OpenMeteoClient().fetch(Places.stowe)
            set("openmeteo", .ok, "\(d.days.count) days, \(d.minutelyTimes.count) 15-minute steps.")
        } catch {
            set("openmeteo", .fail, "\(error)")
        }

        do {
            let d = try await NWSClient().latestDiscussion()
            set("nws", .ok, "Issued \(d.issued.map { Fmt.clock($0) } ?? "?"). \(d.synopsis.prefix(80))…")
        } catch {
            set("nws", .fail, "\(error)")
        }

        await checkStowe()

        let log = Store.load([String].self, "refreshLog") ?? []
        let bgRuns = log.filter { !$0.hasSuffix("foreground") && !$0.hasSuffix("manual") }
        set("refresh", bgRuns.isEmpty ? .warn : .ok,
            bgRuns.isEmpty ? "None yet. iOS schedules these; check back tomorrow." : bgRuns.suffix(5).joined(separator: "\n"))
    }

    func checkStowe() async {
        do {
            let data = try await URLSessionHTTPClient().get(StoweReportClient.terrainURL, headers: [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Upslope/1.0"
            ])
            let html = String(decoding: data, as: UTF8.self)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("stowe-terrain.html")
            try? data.write(to: file)
            stoweHTMLFile = file
            guard html.contains("FR.TerrainStatusFeed") else {
                set("stowe", .fail, "Got \(data.count) bytes but no terrain feed. Share the page below so Claude can adapt the parser.")
                return
            }
            let r = try StoweReportParser.parse(terrainHTML: html, snowHTML: nil, now: Date())
            let watched = Store.settings.watchList.map { n in "\(n): \(r.status(of: n).map { $0.isOpen ? "open" : "closed" } ?? "not found")" }
            set("stowe", r.trails.isEmpty ? .warn : .ok,
                "\(r.trails.count) trails, \(r.lifts.count) lifts.\n" + watched.joined(separator: "\n"))
        } catch {
            set("stowe", .fail, "Blocked or offline: \(error)")
        }
    }
}
