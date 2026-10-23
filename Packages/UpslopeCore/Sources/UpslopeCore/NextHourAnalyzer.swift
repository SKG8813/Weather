import Foundation

/// Thresholds from PLAN.md §3. Rates are inches per hour.
public enum IntensityRules {
    /// Below this liquid rate we treat it as dry.
    public static let traceRate = 0.005
    /// Minimum probability for a minute to count as wet.
    public static let minProbability = 0.5
    /// Snow-to-liquid ratio used to turn liquid rate into snowfall rate.
    public static let snowRatio = 10.0

    /// Snowfall (not liquid) rate for a liquid-equivalent rate.
    public static func snowfallRate(liquid: Double) -> Double { liquid * snowRatio }

    public static func intensity(rate liquid: Double, type: PrecipType) -> Intensity {
        guard liquid >= traceRate, type != .none else { return .none }
        switch type {
        case .snow:
            let s = snowfallRate(liquid: liquid)
            if s < 0.5 { return .light }
            if s < 1.0 { return .moderate }
            return .heavy
        default:
            if liquid < 0.1 { return .light }
            if liquid < 0.3 { return .moderate }
            return .heavy
        }
    }

    /// The rate people care about: snowfall for snow, liquid for everything else.
    public static func displayRate(liquid: Double, type: PrecipType) -> Double {
        type == .snow ? snowfallRate(liquid: liquid) : liquid
    }
}

/// One precipitation event inside the next-hour window.
public struct PrecipEvent: Codable, Sendable, Equatable {
    public var start: Date
    /// Last wet moment inside the window.
    public var end: Date
    /// True if it is still wet at the end of the forecast window.
    public var continuesPastWindow: Bool
    public var type: PrecipType
    public var peakIntensity: Intensity
    /// Peak in display units (snowfall in/hr for snow, liquid in/hr otherwise).
    public var peakRate: Double
    public var peakTime: Date
    /// Liquid-equivalent total in inches.
    public var totalLiquid: Double
    /// Snowfall total in inches (0 for rain).
    public var totalSnow: Double
    /// More than one wet stretch separated by short breaks.
    public var onAndOff: Bool

    public var durationMinutes: Int { max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }

    /// The total in the units people expect: snow inches for snow, liquid otherwise.
    public var displayTotal: Double { type == .snow ? totalSnow : totalLiquid }
}

public enum NextHourState: Codable, Sendable, Equatable {
    /// Nothing in the window.
    case dry
    /// An event starts later in the window.
    case upcoming(PrecipEvent, minutesUntil: Int)
    /// It is wet right now.
    case ongoing(PrecipEvent, minutesLeft: Int)

    public var event: PrecipEvent? {
        switch self {
        case .dry: return nil
        case .upcoming(let e, _), .ongoing(let e, _): return e
        }
    }
}

public enum NextHourAnalyzer {
    /// A dry break shorter than this (minutes) is merged into one on-and-off event.
    public static let mergeGapMinutes = 10
    /// A wet stretch must last at least this long (minutes) to count.
    public static let minWetMinutes = 3

    public static func analyze(_ hour: NextHour, now: Date) -> NextHourState {
        let step = max(1, hour.stepMinutes)
        let points = hour.points
            .filter { $0.time.addingTimeInterval(Double(step) * 60) > now }
            .sorted { $0.time < $1.time }
        guard !points.isEmpty else { return .dry }

        let wet = points.map(isWet)

        // Find wet runs as index ranges.
        var runs: [ClosedRange<Int>] = []
        var runStart: Int?
        for (i, w) in wet.enumerated() {
            if w, runStart == nil { runStart = i }
            if !w, let s = runStart { runs.append(s...(i - 1)); runStart = nil }
        }
        if let s = runStart { runs.append(s...(points.count - 1)) }

        // Drop runs that are too short to matter.
        let minSteps = max(1, Int((Double(minWetMinutes) / Double(step)).rounded(.up)))
        runs = runs.filter { $0.count >= minSteps }
        guard let first = runs.first else { return .dry }

        // Merge later runs separated by short gaps.
        let maxGapSteps = max(0, mergeGapMinutes / step)
        var merged = first
        var pieces = 1
        for r in runs.dropFirst() {
            let gap = r.lowerBound - merged.upperBound - 1
            if gap <= maxGapSteps {
                merged = merged.lowerBound...r.upperBound
                pieces += 1
            } else {
                break
            }
        }

        let slice = Array(points[merged])
        let stepHours = Double(step) / 60
        var totalLiquid = 0.0
        var totalSnow = 0.0
        var weight: [PrecipType: Double] = [:]
        var peak = slice[0]
        for p in slice where isWet(p) {
            let amount = p.rate * stepHours
            totalLiquid += amount
            if p.type == .snow { totalSnow += IntensityRules.snowfallRate(liquid: amount) }
            if p.type == .mix { totalSnow += IntensityRules.snowfallRate(liquid: amount) * 0.5 }
            weight[p.type, default: 0] += amount
            if p.rate > peak.rate { peak = p }
        }
        let type = dominantType(weight)
        let start = slice[0].time
        let lastWet = slice.last(where: isWet) ?? slice[slice.count - 1]
        let end = lastWet.time.addingTimeInterval(Double(step) * 60)
        let continues = merged.upperBound == points.count - 1

        let event = PrecipEvent(
            start: start,
            end: end,
            continuesPastWindow: continues,
            type: type,
            peakIntensity: IntensityRules.intensity(rate: peak.rate, type: type),
            peakRate: IntensityRules.displayRate(liquid: peak.rate, type: type),
            peakTime: peak.time,
            totalLiquid: totalLiquid,
            totalSnow: totalSnow,
            onAndOff: pieces > 1
        )

        if start <= now {
            let left = Int((end.timeIntervalSince(now) / 60).rounded())
            return .ongoing(event, minutesLeft: max(0, left))
        }
        let until = Int((start.timeIntervalSince(now) / 60).rounded())
        return .upcoming(event, minutesUntil: max(0, until))
    }

    static func isWet(_ p: MinutePoint) -> Bool {
        p.type != .none && p.rate >= IntensityRules.traceRate && p.probability >= IntensityRules.minProbability
    }

    static func dominantType(_ weight: [PrecipType: Double]) -> PrecipType {
        let snow = weight[.snow, default: 0]
        let rain = weight[.rain, default: 0]
        let mix = weight[.mix, default: 0]
        let total = snow + rain + mix
        guard total > 0 else { return .rain }
        if mix / total >= 0.3 || (snow > 0 && rain > 0 && min(snow, rain) / total >= 0.25) { return .mix }
        return snow >= rain ? .snow : .rain
    }
}
