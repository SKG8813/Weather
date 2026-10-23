import Foundation

public enum SnarkLevel: String, Codable, Sendable, CaseIterable {
    case mild, standard, unhinged

    var rank: Int {
        switch self {
        case .mild: return 0
        case .standard: return 1
        case .unhinged: return 2
        }
    }
}

/// PG-13 one-liners. Picks are deterministic per event so a line doesn't change
/// every time the widget refreshes.
public enum Snark {
    struct Line {
        let text: String
        let level: SnarkLevel
        init(_ text: String, _ level: SnarkLevel = .mild) {
            self.text = text
            self.level = level
        }
    }

    public static func line(for state: NextHourState, level: SnarkLevel, seed: Int? = nil) -> String {
        let pool: [Line]
        let key: Int
        switch state {
        case .dry:
            pool = dry
            key = seed ?? Int(Date().timeIntervalSince1970 / 3600)
        case .upcoming(let e, _), .ongoing(let e, _):
            pool = lines(for: e, ongoing: { if case .ongoing = state { return true } else { return false } }())
            key = seed ?? Int(e.start.timeIntervalSince1970 / 60)
        }
        return pick(pool, level: level, seed: key)
    }

    public static func trail(_ name: String, isOpen: Bool, level: SnarkLevel, seed: Int = 0) -> String {
        let pool = isOpen ? trailOpen : trailClosed
        return pick(pool, level: level, seed: seed &+ name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
            .replacingOccurrences(of: "{trail}", with: name)
    }

    /// For the Mansfield hero: rain at the base, snow up top, and friends.
    public static func mountain(upperSnow24h: Double, baseRain24h: Double, windHold: WindHoldRisk, level: SnarkLevel, seed: Int = 0) -> String {
        var pool: [Line]
        if upperSnow24h >= 6 { pool = mountainDump }
        else if upperSnow24h >= 1 && baseRain24h >= 0.1 { pool = mountainSplit }
        else if upperSnow24h >= 1 { pool = mountainSnow }
        else if baseRain24h >= 0.1 { pool = mountainRain }
        else { pool = mountainDry }
        if windHold >= .elevated { pool += mountainWind }
        return pick(pool, level: level, seed: seed)
    }

    static func pick(_ pool: [Line], level: SnarkLevel, seed: Int) -> String {
        let allowed = pool.filter { $0.level.rank <= level.rank }
        let choices = allowed.isEmpty ? pool : allowed
        guard !choices.isEmpty else { return "" }
        let i = ((seed % choices.count) + choices.count) % choices.count
        return choices[i].text
    }

    static func lines(for e: PrecipEvent, ongoing: Bool) -> [Line] {
        if e.onAndOff { return onAndOff }
        switch (e.type, e.peakIntensity, ongoing) {
        case (.snow, .heavy, _): return snowHeavy
        case (.snow, .moderate, _): return snowModerate
        case (.snow, _, true): return snowLightNow
        case (.snow, _, false): return snowLight
        case (.mix, _, _): return mix
        case (_, .heavy, _): return rainHeavy
        case (_, .moderate, _): return rainModerate
        case (_, _, true): return rainLightNow
        default: return rainLight
        }
    }

    // MARK: - Pools

    static let dry: [Line] = [
        Line("Dry for the hour. Don't get used to it."),
        Line("Nothing falling. Go outside, you gremlin.", .standard),
        Line("Clear for now. Vermont is plotting something."),
        Line("Zero precip. Enjoy the rare privilege.", .standard),
        Line("Dry. Suspiciously dry. Keep an eye on it.", .unhinged)
    ]

    static let snowLight: [Line] = [
        Line("Flurries incoming. Cute. Not a powder day."),
        Line("Light snow on the way. Pretty, useless, pretty useless.", .standard),
        Line("A dusting's coming. Mansfield calls this a warm-up.", .standard),
        Line("Snow-ish. Lower your expectations accordingly.", .unhinged)
    ]

    static let snowLightNow: [Line] = [
        Line("Flakes in the air. Act natural."),
        Line("It's snowing. Barely. Don't make it weird.", .standard)
    ]

    static let snowModerate: [Line] = [
        Line("Real snow incoming. Wax something."),
        Line("Proper snow on the way. Find your goggles, they're in the car.", .standard),
        Line("Solid snow rates. The chairlift is about to get damn pretty.", .unhinged)
    ]

    static let snowHeavy: [Line] = [
        Line("Black-diamond snowfall incoming. Call in sick."),
        Line("Heavy snow. Cancel your plans. Your boss skis too, probably.", .standard),
        Line("It's about to dump. Hell yes. Clear your calendar.", .unhinged),
        Line("Whiteout rates. Drive like your grandmother is watching.", .standard)
    ]

    static let rainLight: [Line] = [
        Line("Light rain on the way. Hood up, drama down."),
        Line("Drizzle incoming. The worst kind of wet.", .standard),
        Line("A little rain. Nothing a hat can't fix. Probably.", .standard)
    ]

    static let rainLightNow: [Line] = [
        Line("Drizzling. Vermont's way of saying 'meh'."),
        Line("It's raining a little. You'll live.", .standard)
    ]

    static let rainModerate: [Line] = [
        Line("Steady rain coming. Bring the real jacket, not the cute one."),
        Line("Rain incoming. Your socks are already nervous.", .standard),
        Line("Honest-to-god rain. Plan accordingly, or don't and suffer.", .unhinged)
    ]

    static let rainHeavy: [Line] = [
        Line("Downpour incoming. Get inside or get soaked."),
        Line("Heavy rain. The kind that laughs at umbrellas.", .standard),
        Line("It's going to piss down. Stay put.", .unhinged)
    ]

    static let mix: [Line] = [
        Line("Wintry mix on the way. Nobody asked for this."),
        Line("Sleet-ish garbage incoming. Watch the steps.", .standard),
        Line("Mix incoming. Mother Nature can't make up her damn mind.", .unhinged)
    ]

    static let onAndOff: [Line] = [
        Line("On-and-off showers. Commitment issues, much?"),
        Line("Stop, start, stop. The sky is buffering.", .standard)
    ]

    static let trailOpen: [Line] = [
        Line("{trail} is open. Go before the masses."),
        Line("{trail}: open. Your legs have been notified.", .standard),
        Line("{trail} is open. Hug the trees with your eyes, not your face.", .standard)
    ]

    static let trailClosed: [Line] = [
        Line("{trail} is still closed. Patience, hero."),
        Line("{trail}: closed. Needs more snow, and so do you.", .standard),
        Line("{trail} is closed. Don't even think about the rope.", .standard)
    ]

    static let mountainDump: [Line] = [
        Line("Mansfield is getting buried. Clear your calendar."),
        Line("Big totals up top. Your knees are going to hate you. Worth it.", .standard)
    ]
    static let mountainSplit: [Line] = [
        Line("Rain at the base, snow on top. Classic Mansfield. Ski high, drink low."),
        Line("Wet at the bottom, white at the top. Ride the gondola and ignore the parking lot.", .standard)
    ]
    static let mountainSnow: [Line] = [
        Line("Snow up top. The mountain is doing its thing."),
        Line("Fresh stuff on Mansfield. Go earn it.", .standard)
    ]
    static let mountainRain: [Line] = [
        Line("Rain on the mountain. Groomers turn to mashed potatoes. Sorry."),
        Line("Rain up high. Damn shame. Go to the brewery.", .standard)
    ]
    static let mountainDry: [Line] = [
        Line("Quiet on Mansfield. Groomers and sunshine, if you're lucky."),
        Line("No new snow. Corduroy hunters, rise.", .standard)
    ]
    static let mountainWind: [Line] = [
        Line("Wind's ripping up top. The gondola may sit this one out."),
        Line("Gusty on the Chin. Hold onto your hat. And your dignity.", .standard)
    ]
}
