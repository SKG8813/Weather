import SwiftUI
import UpslopeCore

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(UFont.body(12, weight: .semibold, relativeTo: .caption))
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var detail: String?
    var mark: Intensity?
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: label)
            Text(value)
                .font(UFont.display(30))
                .foregroundStyle(highlight ? Theme.accent : Theme.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let detail {
                HStack(spacing: 5) {
                    if let mark { IntensityMark(intensity: mark, size: 10) }
                    Text(detail).font(UFont.body(13)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            MansfieldShape()
                .fill(Theme.accent)
                .frame(width: 34, height: 18)
            Text("UPSLOPE")
                .font(UFont.display(22))
                .tracking(2.5)
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement()
        .accessibilityLabel("Upslope")
    }
}

/// Here / Stowe switch.
struct PlacePicker: View {
    @Binding var place: PlaceChoice

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PlaceChoice.allCases) { p in
                Button {
                    place = p
                } label: {
                    HStack(spacing: 5) {
                        if p == .here { Image(systemName: "location.fill").font(.system(size: 11, weight: .bold)) }
                        Text(p.label)
                    }
                    .font(UFont.body(14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .foregroundStyle(place == p ? Theme.onAccent : Theme.muted)
                    .background(place == p ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(place == p ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Banner for old or missing data.
struct StaleBanner: View {
    var forecast: Forecast?
    var now: Date

    var body: some View {
        if let f = forecast, f.isStale(now: now) {
            Label("As of \(Fmt.clock(f.fetchedAt)). Pull to refresh.", systemImage: "clock.arrow.circlepath")
                .font(UFont.body(13, weight: .medium))
                .foregroundStyle(Theme.muted)
        } else if forecast == nil {
            Label("No forecast yet. Pull to refresh.", systemImage: "wifi.exclamationmark")
                .font(UFont.body(13, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
    }
}
