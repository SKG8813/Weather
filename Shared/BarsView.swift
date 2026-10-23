import SwiftUI
import UpslopeCore

/// 60 one-minute bars. Heavy minutes use the accent color in full-color contexts.
struct BarsView: View {
    var bars: [NextHourBar]
    var height: CGFloat
    var monochrome = false
    var spacing: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(bars, id: \.minute) { b in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(b))
                        .frame(height: max(2, CGFloat(min(b.level, 1.2) / 1.2) * geo.size.height))
                        .opacity(b.level > 0 ? 1 : 0.35)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilitySummary(bars))
    }

    func color(_ b: NextHourBar) -> Color {
        if monochrome { return .primary }
        if b.level <= 0 { return Theme.line }
        return b.intensity == .heavy ? Theme.accent : Theme.bar
    }

    static func accessibilitySummary(_ bars: [NextHourBar]) -> String {
        guard let first = bars.first(where: { $0.level > 0 }) else { return "Dry for the next hour" }
        let peak = bars.max(by: { $0.level < $1.level })!
        return "Precipitation from minute \(first.minute), peaking \(peak.intensity.label.lowercased()) at minute \(peak.minute)"
    }
}
