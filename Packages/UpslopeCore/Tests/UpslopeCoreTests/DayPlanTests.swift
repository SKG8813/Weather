import XCTest
@testable import UpslopeCore

final class DayPlanTests: XCTestCase {
    let tz = TimeZone(identifier: "America/New_York")!

    /// Midnight local on a winter day.
    var midnight: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: 2026, month: 12, day: 28))!
    }

    /// 30 hours from local midnight. `wet(h)` returns (rain, snowfall) in inches for hour h.
    func hours(peakTempAt: Int = 14, wet: (Int) -> (Double, Double) = { _ in (0, 0) }) -> [HourPoint] {
        (0..<30).map { h in
            let (rain, snow) = wet(h)
            let temp = 30 + 15 * cos(Double(h - peakTempAt) / 24 * 2 * .pi)
            return HourPoint(time: midnight.addingTimeInterval(Double(h) * 3600), temperature: temp, feelsLike: temp - 6,
                             precipitation: rain + snow / 10, rain: rain, snowfall: snow,
                             probability: rain + snow > 0 ? 0.8 : 0.05, windSpeed: Double(5 + h % 7),
                             windGust: Double(15 + h % 9), windBearing: 300, cloudCover: rain + snow > 0 ? 100 : 15)
        }
    }

    func day(_ hs: [HourPoint]) -> DayForecast {
        DayForecast(date: midnight, high: 45, low: 15, precipChance: hs.map(\.probability).max() ?? 0,
                    rainInches: 0, snowInches: 0, symbol: .sun,
                    sunrise: midnight.addingTimeInterval(7.3 * 3600), sunset: midnight.addingTimeInterval(16.4 * 3600))
    }

    func testDryDay() {
        let hs = hours()
        let p = DayPlanner.plan(for: day(hs), hours: hs, timeZone: tz)
        XCTAssertEqual(p.parts.map(\.name), [.morning, .afternoon, .night])
        XCTAssertEqual(p.parts.map(\.symbol), [.sun, .sun, .sun])
        XCTAssertTrue(p.windows.isEmpty)
        XCTAssertEqual(p.summary, "Dry all day. High 45° around 2 pm.")
        XCTAssertEqual(p.high, 45, accuracy: 0.01)
        XCTAssertEqual(Fmt.hour(p.lowAt!, timeZone: tz), "2 am")
        XCTAssertEqual(p.parts[2].temperature, 15, accuracy: 0.5, "night shows its coldest")
        XCTAssertNotNil(p.sunrise)
    }

    func testSnowMovesInAfterADryMorning() {
        let hs = hours { h in
            guard (14..<21).contains(h) else { return (0, 0) }
            return (0, h == 17 ? 0.8 : 0.45)
        }
        let p = DayPlanner.plan(for: day(hs), hours: hs, timeZone: tz)
        XCTAssertEqual(p.windows.count, 1)
        XCTAssertEqual(p.windows[0].type, .snow)
        XCTAssertEqual(p.summary, "Dry morning, then snow 2–9 pm. 3–4″ of snow, heaviest around 5 pm.")
        XCTAssertEqual(p.parts[0].symbol, .sun)
        XCTAssertEqual(p.parts[1].symbol, .snow)
        XCTAssertEqual(p.parts[2].symbol, .snow)
        XCTAssertNil(p.changeover)
        XCTAssertEqual(p.snowTotal, 3.5, accuracy: 0.001)
    }

    func testRainTurningToSnow() {
        let hs = hours { h in
            if (10..<14).contains(h) { return (0.06, 0) }
            if (14..<19).contains(h) { return (0, 0.5) }
            return (0, 0)
        }
        let p = DayPlanner.plan(for: day(hs), hours: hs, timeZone: tz)
        XCTAssertEqual(p.changeover, "Rain turns to snow ~2 pm")
        XCTAssertEqual(p.windows.count, 1)
        XCTAssertTrue(p.summary.hasPrefix("Rain from 10 am, turning to snow ~2 pm, ending ~7 pm."), p.summary)
        XCTAssertTrue(p.summary.contains("of snow and 0.2″ of rain"), p.summary)
    }

    func testShortBreakKeepsOneWindowLongBreakSplits() {
        let one = DayPlanner.wetWindows(hours { h in [8, 9, 11].contains(h) ? (0.05, 0) : (0, 0) })
        XCTAssertEqual(one.count, 1)
        let two = DayPlanner.wetWindows(hours { h in [8, 9, 13].contains(h) ? (0.05, 0) : (0, 0) })
        XCTAssertEqual(two.count, 2)
    }

    func testWithoutHourlyDataFallsBackToTheDailyNumbers() {
        var d = day([])
        d.snowInches = 4
        let p = DayPlanner.plan(for: d, hours: [], timeZone: tz)
        XCTAssertTrue(p.parts.isEmpty)
        XCTAssertEqual(p.summary, "3–5″ of snow expected.")
    }

    func testHourRanges() {
        XCTAssertEqual(Fmt.hourRange(midnight.addingTimeInterval(14 * 3600), midnight.addingTimeInterval(21 * 3600), timeZone: tz), "2–9 pm")
        XCTAssertEqual(Fmt.hourRange(midnight.addingTimeInterval(10 * 3600), midnight.addingTimeInterval(14 * 3600), timeZone: tz), "10 am–2 pm")
    }

    func testSkiVerdict() {
        XCTAssertEqual(DayPlanner.skiVerdict(upperSnow: 8, upperRain: 0, windHold: .low, windFrom: nil, timeZone: tz),
                       "Big day up top: about 6–10″ on the upper mountain.")
        XCTAssertEqual(DayPlanner.skiVerdict(upperSnow: 0, upperRain: 0.3, windHold: .elevated, windFrom: midnight.addingTimeInterval(11 * 3600), timeZone: tz),
                       "Rain up high. Groomers will be mashed potatoes. Wind holds possible after 11 am.")
    }

    func testRealOpenMeteoDayHasThreeParts() throws {
        let d = try OpenMeteoData(json: fixture("om-upper.json"))
        let p = DayPlanner.plan(for: d.days[1], hours: d.hours, timeZone: d.timeZone)
        XCTAssertEqual(p.parts.count, 3)
        XCTAssertEqual(p.high, d.days[1].high, accuracy: 1.5, "hourly high should match the daily high")
        XCTAssertFalse(p.summary.isEmpty)
    }
}
