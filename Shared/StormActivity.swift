import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for one precipitation event ("Track this storm").
struct StormAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var typeName: String
        var start: Date
        var end: Date
        var continuesPastWindow: Bool
        var peakRate: Double
        var peakTime: Date
        var total: Double
        /// 0...1.2 per minute from the start of `barsFrom`.
        var bars: [Double]
        var barsFrom: Date
        var heavyFromLevel: Double
        var snark: String
    }

    var placeName: String
}
#endif
