import XCTest
@testable import UpslopeCore

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Serves canned bodies by URL substring.
struct StubHTTP: HTTPClient {
    var routes: [(String, Data)]
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        guard let hit = routes.first(where: { url.absoluteString.contains($0.0) }) else { throw HTTPError.status(404) }
        return hit.1
    }
}

final class ClientParsingTests: XCTestCase {
    func testOpenMeteoRealResponse() throws {
        let d = try OpenMeteoData(json: fixture("om-upper.json"))
        XCTAssertEqual(d.timeZone.identifier, "America/New_York")
        XCTAssertEqual(d.days.count, 7)
        XCTAssertEqual(d.hourlyTimes.count, 168)
        let nh = try XCTUnwrap(d.nextHour)
        XCTAssertEqual(nh.stepMinutes, 15)
        XCTAssertEqual(nh.points.count, 8)
        let c = try XCTUnwrap(d.current)
        XCTAssertEqual(c.temperature, 31.1, accuracy: 0.01)
        // Freezing level arrives in feet already.
        XCTAssertNotNil(d.hourlyValue("freezing_level_height", at: 0))
        for day in d.days { XCTAssertGreaterThanOrEqual(day.high, day.low) }
    }

    func testOpenMeteoUnitNormalization() {
        XCTAssertEqual(OpenMeteoData.normalize(0, unit: "°C")!, 32, accuracy: 0.001)
        XCTAssertEqual(OpenMeteoData.normalize(25.4, unit: "mm")!, 1, accuracy: 0.001)
        XCTAssertEqual(OpenMeteoData.normalize(1000, unit: "m")!, 3280.84, accuracy: 0.01)
        XCTAssertEqual(OpenMeteoData.normalize(12, unit: "mp/h")!, 12)
    }

    func testOpenMeteoURLAsksForUSUnitsAndElevation() {
        let url = OpenMeteoClient().url(for: Places.mansfieldUpper, elevationFeet: 3600).absoluteString
        XCTAssertTrue(url.contains("elevation=1097"))
        XCTAssertTrue(url.contains("precipitation_unit=inch"))
        XCTAssertTrue(url.contains("timeformat=unixtime"))
    }

    func testPirateWeather() throws {
        let r = try PirateWeatherClient.parse(fixture("pirate.json"))
        XCTAssertEqual(r.current?.temperature, 31.2)
        XCTAssertEqual(r.nextHour?.points.count, 6)
        XCTAssertEqual(r.nextHour?.points[3].type, .snow)
        XCTAssertEqual(r.nextHour?.points[0].type, PrecipType.none)
        XCTAssertEqual(r.days.first?.snowInches, 1.5)
        XCTAssertEqual(r.days.first?.symbol, .snow)
    }

    func testForecastServiceFallsBackToOpenMeteoWithoutKey() async throws {
        let http = StubHTTP(routes: [("open-meteo", try fixture("om-upper.json"))])
        let f = try await ForecastService(pirateKey: nil, http: http).forecast(placeName: "Stowe", at: Places.stowe)
        XCTAssertEqual(f.nextHourSource, .openMeteo)
        XCTAssertEqual(f.days.count, 7)
        XCTAssertNotNil(f.current)
    }

    func testForecastServicePrefersPirateForNextHour() async throws {
        let http = StubHTTP(routes: [("pirateweather", try fixture("pirate.json")), ("open-meteo", try fixture("om-upper.json"))])
        let f = try await ForecastService(pirateKey: "test", http: http).forecast(placeName: "Stowe", at: Places.stowe)
        XCTAssertEqual(f.nextHourSource, .pirateWeather)
        XCTAssertEqual(f.current?.temperature, 31.2)
        XCTAssertEqual(f.days.count, 7, "7-day still comes from Open-Meteo")
    }

    func testUnsubstitutedBuildSettingIsTreatedAsNoKey() {
        XCTAssertNil(ForecastService(pirateKey: "$(PIRATE_WEATHER_KEY)").pirate)
    }

    func testMountainFromRealResponses() throws {
        let upper = try OpenMeteoData(json: fixture("om-upper.json"))
        let base = try OpenMeteoData(json: fixture("om-base.json"))
        let now = upper.hourlyTimes[0]
        let m = MountainRules.build(upper: upper, base: base, now: now)
        XCTAssertNotNil(m.upper.current)
        XCTAssertNotNil(m.base.current)
        XCTAssertLessThan(m.upper.current!.temperature, m.base.current!.temperature, "colder up top")
        XCTAssertNotNil(m.snowLineFeet)
        XCTAssertEqual(m.upperDailySnow.count, 7)
    }

    func testUpslopeAndWindHoldRules() throws {
        // Build a synthetic Open-Meteo payload: 12 hours of NW flow, cold, moist, gusty.
        let t0 = 1_792_800_000.0 // 2026-12-? local times don't matter for upslope
        var hours: [Double] = []
        for i in 0..<24 { hours.append(t0 + Double(i) * 3600) }
        func col(_ v: Double) -> [Double] { Array(repeating: v, count: 24) }
        let json: [String: Any] = [
            "timezone": "America/New_York", "utc_offset_seconds": -18000,
            "hourly": [
                "time": hours, "wind_direction_850hPa": col(300), "wind_speed_850hPa": col(30),
                "temperature_850hPa": col(14), "relative_humidity_850hPa": col(90), "wind_gusts_10m": col(52),
                "freezing_level_height": col(900), "snowfall": col(0.3), "rain": col(0)
            ],
            "hourly_units": ["freezing_level_height": "ft"]
        ]
        let d = try OpenMeteoData(json: JSONSerialization.data(withJSONObject: json))
        let m = MountainRules.build(upper: d, base: d, now: Date(timeIntervalSince1970: t0))
        XCTAssertEqual(m.upslope, .strong)
        XCTAssertEqual(m.windHold, .high)
        XCTAssertEqual(m.snowLineFeet, 0)
        XCTAssertNotNil(m.snowLineAtBaseBy)
        XCTAssertEqual(m.upper.snow24h, 7.2, accuracy: 0.01)
    }

    func testNWSDiscussionRealProduct() throws {
        XCTAssertEqual(try NWSClient.latestID(fixture("nws-list.json")), "fd1317dc-b74e-484e-99ae-0a5f385fcab0")
        let d = try NWSClient.parseProduct(fixture("nws-product.json"), url: URL(string: "https://api.weather.gov/products/x")!)
        XCTAssertNotNil(d.issued)
        XCTAssertTrue(d.synopsis.hasPrefix("1. Dry and quiet weather"), d.synopsis)
        XCTAssertTrue(d.synopsis.contains("\n2. Dry weather"))
        XCTAssertFalse(d.synopsis.contains("As of"))
    }

    func testNWSFallsBackToSynopsis() {
        let text = "STUFF\n.SYNOPSIS...\nIssued at 300 AM\nLake effect snow\nlikely tonight.\n\n&&\n"
        XCTAssertEqual(NWSClient.synopsis(from: text), "Lake effect snow likely tonight.")
    }
}

final class StoweReportTests: XCTestCase {
    func report() throws -> ResortReport {
        try StoweReportParser.parse(
            terrainHTML: String(decoding: fixture("stowe-terrain.html"), as: UTF8.self),
            snowHTML: String(decoding: fixture("stowe-snow.html"), as: UTF8.self),
            now: Date())
    }

    func testPrefersStringFeedAndReadsLifts() throws {
        let r = try report()
        XCTAssertEqual(r.reportDate, "2026-12-28T06:12:00-05:00")
        XCTAssertEqual(r.lifts.count, 4)
        XCTAssertEqual(r.liftsOpen, 2, "Open and OnHold count as running")
    }

    func testTrailsAndWatchList() throws {
        let r = try report()
        XCTAssertEqual(r.trails.count, 6)
        XCTAssertEqual(r.trailsOpen, 4)
        XCTAssertEqual(r.percentOpen!, 4.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(r.status(of: "upper national")?.isOpen, true)
        XCTAssertEqual(r.status(of: "Goat")?.isOpen, false)
        XCTAssertEqual(r.status(of: "Starr Glades")?.isOpen, true)
        XCTAssertNil(r.status(of: "Spruce Peak"))
    }

    func testSnowNumbers() throws {
        let r = try report()
        XCTAssertEqual(r.new24h, 6)
        XCTAssertEqual(r.new7d, 14)
        XCTAssertEqual(r.baseDepth, 42)
    }

    func testMissingFeedThrows() {
        XCTAssertThrowsError(try StoweReportParser.parse(terrainHTML: "<html>blocked</html>", snowHTML: nil, now: Date()))
    }

    func testTrailWatchReportsOnlyNewOpenings() throws {
        let r = try report()
        let watch = TrailWatch.defaultWatchList
        XCTAssertEqual(TrailWatch.justOpened(previous: ["Upper National": false, "Starr Glades": true, "Goat": false], report: r, watch: watch), ["Upper National"])
        XCTAssertEqual(TrailWatch.justOpened(previous: [:], report: r, watch: watch), [], "first run never alerts")
        XCTAssertEqual(TrailWatch.snapshot(r, watch: watch), ["Upper National": true, "Goat": false, "Starr Glades": true])
    }
}

final class TextTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(Fmt.inches(0.6), "0.6″")
        XCTAssertEqual(Fmt.inches(2.0), "2″")
        XCTAssertEqual(Fmt.inches(0.04), "<0.1″")
        XCTAssertEqual(Fmt.inchRange(4), "3–5″")
        XCTAssertEqual(Fmt.rate(1.14), "1.1″/hr")
        XCTAssertEqual(Fmt.shortMinutes(12), "12m")
        XCTAssertEqual(Fmt.shortMinutes(65), "1h5m")
        XCTAssertEqual(Fmt.minutes(40), "40 min")
        XCTAssertEqual(Fmt.compass(300), "NW")
        XCTAssertEqual(Fmt.compass(359), "N")
        XCTAssertEqual(Fmt.feet(2412), "2,400′")
        XCTAssertEqual(Fmt.clock(Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "America/New_York")!), "7:00")
    }

    func testSnarkIsStablePerEventAndRespectsLevel() {
        let start = Date(timeIntervalSince1970: 1_792_800_720)
        let e = PrecipEvent(start: start, end: start.addingTimeInterval(2400), continuesPastWindow: false, type: .snow,
                            peakIntensity: .heavy, peakRate: 1.1, peakTime: start, totalLiquid: 0.06, totalSnow: 0.6, onAndOff: false)
        let a = Snark.line(for: .upcoming(e, minutesUntil: 12), level: .standard)
        let b = Snark.line(for: .upcoming(e, minutesUntil: 8), level: .standard)
        XCTAssertEqual(a, b, "same event, same line")
        for seed in 0..<20 {
            let mild = Snark.line(for: .upcoming(e, minutesUntil: 1), level: .mild, seed: seed)
            XCTAssertTrue(Snark.snowHeavy.contains { $0.text == mild && $0.level == .mild })
        }
    }

    func testSnarkStaysPG13() {
        let banned = ["fuck", "shit", "bitch", "cunt", "asshole"]
        let all = Snark.dry + Snark.snowLight + Snark.snowLightNow + Snark.snowModerate + Snark.snowHeavy + Snark.rainLight + Snark.rainLightNow
            + Snark.rainModerate + Snark.rainHeavy + Snark.mix + Snark.onAndOff + Snark.trailOpen + Snark.trailClosed
            + Snark.mountainDump + Snark.mountainSplit + Snark.mountainSnow + Snark.mountainRain + Snark.mountainDry + Snark.mountainWind
        for line in all {
            for word in banned { XCTAssertFalse(line.text.lowercased().contains(word), line.text) }
        }
        XCTAssertEqual(Snark.trail("Goat", isOpen: false, level: .mild), "Goat is still closed. Patience, hero.")
    }

    func testHeadlines() {
        let start = Date(timeIntervalSince1970: 1_792_800_720)
        let e = PrecipEvent(start: start, end: start.addingTimeInterval(2400), continuesPastWindow: false, type: .snow,
                            peakIntensity: .heavy, peakRate: 1.1, peakTime: start, totalLiquid: 0.06, totalSnow: 0.6, onAndOff: false)
        XCTAssertEqual(NextHourText.headline(.upcoming(e, minutesUntil: 12)), "Snow in 12 minutes.")
        XCTAssertEqual(NextHourText.compact(.upcoming(e, minutesUntil: 12)), "Snow in 12m")
        XCTAssertEqual(NextHourText.alertTitle(.upcoming(e, minutesUntil: 12)), "Snow in 12 min · ~40 min · up to 1.1″/hr")
        XCTAssertEqual(NextHourText.headline(.dry), "Dry for the hour.")
    }
}
