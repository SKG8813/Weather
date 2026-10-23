import XCTest
@testable import UpslopeCore

final class NextHourAnalyzerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_800_000)

    /// 60 one-minute points; `rate(i)` gives the liquid rate for minute i.
    func hour(type: PrecipType = .snow, probability: Double = 0.9, _ rate: (Int) -> Double) -> NextHour {
        NextHour(points: (0..<60).map { i in
            let r = rate(i)
            return MinutePoint(time: now.addingTimeInterval(Double(i) * 60), rate: r, probability: probability, type: r > 0 ? type : .none)
        }, stepMinutes: 1)
    }

    func testDryHour() {
        XCTAssertEqual(NextHourAnalyzer.analyze(hour { _ in 0 }, now: now), .dry)
    }

    func testUpcomingHeavySnowMatchesTheDesign() throws {
        // Starts at minute 12, lasts to minute 52, peaks ~0.11 in/hr liquid = 1.1″/hr snow.
        let h = hour { i in (12..<52).contains(i) ? 0.11 * pow(sin(.pi * Double(i - 12) / 40), 0.8) + 0.006 : 0 }
        guard case .upcoming(let e, let m) = NextHourAnalyzer.analyze(h, now: now) else { return XCTFail("expected upcoming") }
        XCTAssertEqual(m, 12)
        XCTAssertEqual(e.type, .snow)
        XCTAssertEqual(e.durationMinutes, 40)
        XCTAssertEqual(e.peakIntensity, .heavy)
        XCTAssertEqual(e.peakRate, 1.16, accuracy: 0.05)
        XCTAssertFalse(e.continuesPastWindow)
        XCTAssertFalse(e.onAndOff)
        XCTAssertEqual(e.totalSnow, 0.5, accuracy: 0.1)
    }

    func testOngoingRainThatOutlastsTheWindow() throws {
        let h = hour(type: .rain) { _ in 0.15 }
        guard case .ongoing(let e, _) = NextHourAnalyzer.analyze(h, now: now) else { return XCTFail("expected ongoing") }
        XCTAssertEqual(e.type, .rain)
        XCTAssertEqual(e.peakIntensity, .moderate)
        XCTAssertTrue(e.continuesPastWindow)
    }

    func testShortBreaksMergeIntoOnAndOff() throws {
        let h = hour(type: .rain) { i in (5..<15).contains(i) || (20..<30).contains(i) ? 0.05 : 0 }
        let e = try XCTUnwrap(NextHourAnalyzer.analyze(h, now: now).event)
        XCTAssertTrue(e.onAndOff)
        XCTAssertEqual(e.durationMinutes, 25)
    }

    func testLongBreakEndsTheEvent() throws {
        let h = hour(type: .rain) { i in (5..<15).contains(i) || (40..<50).contains(i) ? 0.05 : 0 }
        let e = try XCTUnwrap(NextHourAnalyzer.analyze(h, now: now).event)
        XCTAssertFalse(e.onAndOff)
        XCTAssertEqual(e.durationMinutes, 10)
    }

    func testBlipsAndUnlikelyPrecipAreIgnored() {
        XCTAssertEqual(NextHourAnalyzer.analyze(hour { i in i == 30 ? 0.2 : 0 }, now: now), .dry, "one-minute blip")
        XCTAssertEqual(NextHourAnalyzer.analyze(hour(probability: 0.3) { _ in 0.2 }, now: now), .dry, "low probability")
        XCTAssertEqual(NextHourAnalyzer.analyze(hour { _ in 0.002 }, now: now), .dry, "below trace")
    }

    func testFifteenMinuteSteps() throws {
        let pts = (0..<4).map { i in
            MinutePoint(time: now.addingTimeInterval(Double(i) * 900), rate: i == 2 ? 0.2 : 0, probability: 0.8, type: i == 2 ? .rain : .none)
        }
        guard case .upcoming(let e, let m) = NextHourAnalyzer.analyze(NextHour(points: pts, stepMinutes: 15), now: now) else {
            return XCTFail("expected upcoming")
        }
        XCTAssertEqual(m, 30)
        XCTAssertEqual(e.durationMinutes, 15)
        XCTAssertEqual(e.totalLiquid, 0.05, accuracy: 0.001)
    }

    func testMixedTypesBecomeMix() throws {
        var h = hour(type: .rain) { i in (10..<40).contains(i) ? 0.05 : 0 }
        for i in 25..<40 { h.points[i].type = .snow }
        XCTAssertEqual(try XCTUnwrap(NextHourAnalyzer.analyze(h, now: now).event).type, .mix)
    }

    func testIntensityThresholds() {
        XCTAssertEqual(IntensityRules.intensity(rate: 0.003, type: .rain), .none)
        XCTAssertEqual(IntensityRules.intensity(rate: 0.05, type: .rain), .light)
        XCTAssertEqual(IntensityRules.intensity(rate: 0.2, type: .rain), .moderate)
        XCTAssertEqual(IntensityRules.intensity(rate: 0.4, type: .rain), .heavy)
        XCTAssertEqual(IntensityRules.intensity(rate: 0.03, type: .snow), .light)    // 0.3″/hr snow
        XCTAssertEqual(IntensityRules.intensity(rate: 0.07, type: .snow), .moderate) // 0.7″/hr
        XCTAssertEqual(IntensityRules.intensity(rate: 0.12, type: .snow), .heavy)    // 1.2″/hr
    }
}

final class AlertPlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_800_000)

    func event(startIn minutes: Double, type: PrecipType = .snow, length: Double = 40) -> PrecipEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return PrecipEvent(start: start, end: start.addingTimeInterval(length * 60), continuesPastWindow: false, type: type,
                           peakIntensity: .heavy, peakRate: 1.1, peakTime: start, totalLiquid: 0.06, totalSnow: 0.6, onAndOff: false)
    }

    func testPostsOnceThenStaysQuiet() {
        let next = NextHourState.upcoming(event(startIn: 12), minutesUntil: 12)
        let (a1, s1) = AlertPlanner.plan(state: AlertState(), next: next, now: now, snark: .standard)
        guard case .post(let content) = a1 else { return XCTFail("expected post") }
        XCTAssertTrue(content.title.hasPrefix("Snow in 12 min"))
        XCTAssertFalse(content.body.isEmpty)

        let later = now.addingTimeInterval(120)
        let (a2, _) = AlertPlanner.plan(state: s1, next: .upcoming(event(startIn: 13), minutesUntil: 10), now: later, snark: .standard)
        XCTAssertEqual(a2, .none, "2 minute shift is not worth a replace")
    }

    func testReplacesWhenStartShiftsOrTypeChanges() {
        let (_, s1) = AlertPlanner.plan(state: AlertState(), next: .upcoming(event(startIn: 12), minutesUntil: 12), now: now, snark: .mild)
        let (a2, s2) = AlertPlanner.plan(state: s1, next: .upcoming(event(startIn: 25), minutesUntil: 25), now: now, snark: .mild)
        guard case .replace(let c2) = a2 else { return XCTFail("expected replace on shift") }
        XCTAssertEqual(c2.id, s1.activeID)

        let (a3, _) = AlertPlanner.plan(state: s2, next: .upcoming(event(startIn: 25, type: .mix), minutesUntil: 25), now: now, snark: .mild)
        guard case .replace = a3 else { return XCTFail("expected replace on type change") }
    }

    func testOngoingStartDriftDoesNotReplace() {
        let (_, s1) = AlertPlanner.plan(state: AlertState(), next: .upcoming(event(startIn: 5), minutesUntil: 5), now: now, snark: .mild)
        let (a2, _) = AlertPlanner.plan(state: s1, next: .ongoing(event(startIn: -10), minutesLeft: 30), now: now.addingTimeInterval(600), snark: .mild)
        XCTAssertEqual(a2, .none)
    }

    func testRemovesAfterThirtyDryMinutesThenAlertsAgain() {
        let (_, s1) = AlertPlanner.plan(state: AlertState(), next: .upcoming(event(startIn: 0, length: 20), minutesUntil: 0), now: now, snark: .mild)
        let (a2, s2) = AlertPlanner.plan(state: s1, next: .dry, now: now.addingTimeInterval(40 * 60), snark: .mild)
        XCTAssertEqual(a2, .none, "only 20 dry minutes since it ended")
        let (a3, s3) = AlertPlanner.plan(state: s2, next: .dry, now: now.addingTimeInterval(55 * 60), snark: .mild)
        XCTAssertEqual(a3, .remove(id: s1.activeID!))
        XCTAssertNil(s3.activeID)
    }

    func testNewEventAfterLongGapPostsEvenWithoutADryCheck() {
        let (_, s1) = AlertPlanner.plan(state: AlertState(), next: .upcoming(event(startIn: 0, length: 10), minutesUntil: 0), now: now, snark: .mild)
        let later = now.addingTimeInterval(90 * 60)
        let fresh = PrecipEvent(start: later.addingTimeInterval(600), end: later.addingTimeInterval(1800), continuesPastWindow: false, type: .rain,
                                peakIntensity: .light, peakRate: 0.05, peakTime: later, totalLiquid: 0.02, totalSnow: 0, onAndOff: false)
        let (a2, _) = AlertPlanner.plan(state: s1, next: .upcoming(fresh, minutesUntil: 10), now: later, snark: .mild)
        guard case .post(let c) = a2 else { return XCTFail("expected new post") }
        XCTAssertNotEqual(c.id, s1.activeID)
    }
}
