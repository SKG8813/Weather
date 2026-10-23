import ActivityKit
import SwiftUI
import UpslopeCore
import WidgetKit

/// "Track this storm": live countdown on the lock screen and in the Dynamic Island.
struct StormLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StormAttributes.self) { context in
            LockScreenStormView(state: context.state, placeName: context.attributes.placeName)
                .activityBackgroundTint(Theme.bg.opacity(0.85))
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.typeName, systemImage: symbol(s.typeName))
                        .font(UFont.display(18))
                        .foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StormCountdown(state: s).font(UFont.display(22)).foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        StormBars(state: s, height: 24)
                        Text("Peak \(Fmt.rate(s.peakRate)) at \(Fmt.clock(s.peakTime)) · \(Fmt.inches(s.total)) total")
                            .font(UFont.body(12, weight: .medium))
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(s.typeName)).foregroundStyle(Theme.accent)
            } compactTrailing: {
                StormCountdown(state: s)
                    .font(UFont.display(15))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: symbol(s.typeName)).foregroundStyle(Theme.accent)
            }
        }
    }

    func symbol(_ type: String) -> String {
        PrecipIcon.symbol(PrecipType(rawValue: type.lowercased()) ?? .rain)
    }
}

struct LockScreenStormView: View {
    var state: StormAttributes.ContentState
    var placeName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(state.typeName) · \(placeName)")
                    .font(UFont.display(18))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(Date() < state.start ? "starts in" : "ends in")
                    .font(UFont.body(13))
                    .foregroundStyle(Theme.muted)
                StormCountdown(state: state)
                    .font(UFont.display(26))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            StormBars(state: state, height: 34)
            HStack {
                Text("Peak \(Fmt.rate(state.peakRate)) at \(Fmt.clock(state.peakTime))")
                Spacer()
                Text("~\(Fmt.inches(state.total)) total")
            }
            .font(UFont.body(13, weight: .medium))
            .foregroundStyle(Theme.soft)
            Text(state.snark)
                .font(UFont.body(14))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
        .padding(16)
    }
}

struct StormBars: View {
    var state: StormAttributes.ContentState
    var height: CGFloat

    var body: some View {
        // Drop bars that are already in the past.
        let skip = max(0, Int(Date().timeIntervalSince(state.barsFrom) / 60))
        let levels = Array(state.bars.dropFirst(skip)) + Array(repeating: 0, count: min(skip, state.bars.count))
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(v >= state.heavyFromLevel ? Theme.accent : (v > 0 ? Color.white : Color.white.opacity(0.3)))
                        .frame(height: max(2, CGFloat(min(v, 1.2) / 1.2) * geo.size.height))
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
        .frame(height: height)
    }
}

/// Ticks on its own between Live Activity updates.
struct StormCountdown: View {
    var state: StormAttributes.ContentState

    var body: some View {
        if Date() < state.start {
            Text(timerInterval: Date()...state.start, countsDown: true).monospacedDigit()
        } else if state.continuesPastWindow {
            Text("1h+")
        } else {
            Text(timerInterval: Date()...max(Date(), state.end), countsDown: true).monospacedDigit()
        }
    }
}
