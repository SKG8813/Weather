import Foundation

/// One bar per minute for the next 60 minutes, shared by the app chart and widgets.
public struct NextHourBar: Codable, Sendable, Equatable, Hashable {
    public var minute: Int
    /// 0...1, where 1 is the bottom of "heavy".
    public var level: Double
    public var intensity: Intensity
    public var type: PrecipType
}

public enum NextHourBars {
    public static func bars(_ hour: NextHour?, now: Date, count: Int = 60) -> [NextHourBar] {
        guard let hour, !hour.points.isEmpty else {
            return (0..<count).map { NextHourBar(minute: $0, level: 0, intensity: .none, type: .none) }
        }
        let step = Double(max(1, hour.stepMinutes)) * 60
        let points = hour.points.sorted { $0.time < $1.time }
        return (0..<count).map { m in
            let t = now.addingTimeInterval(Double(m) * 60)
            let p = points.last(where: { $0.time <= t && t < $0.time.addingTimeInterval(step) })
            guard let p, NextHourAnalyzer.isWet(p) else {
                return NextHourBar(minute: m, level: 0, intensity: .none, type: .none)
            }
            let heavyAt = p.type == .snow ? 0.1 : 0.3 // liquid rate where "heavy" begins
            return NextHourBar(minute: m,
                               level: min(1.2, p.rate / heavyAt),
                               intensity: IntensityRules.intensity(rate: p.rate, type: p.type),
                               type: p.type)
        }
    }
}
