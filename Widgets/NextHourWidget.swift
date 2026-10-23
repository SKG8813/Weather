import SwiftUI
import UpslopeCore
import WidgetKit

struct NextHourEntry: TimelineEntry {
    var date: Date
    var place: PlaceChoice
    var forecast: Forecast?

    var state: NextHourState {
        forecast?.nextHour.map { NextHourAnalyzer.analyze($0, now: date) } ?? .dry
    }
    var bars: [NextHourBar] { NextHourBars.bars(forecast?.nextHour, now: date) }
    var isStale: Bool { forecast?.isStale(now: date) ?? true }
}

struct NextHourProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextHourEntry {
        NextHourEntry(date: Date(), place: .stowe, forecast: nil)
    }

    func snapshot(for configuration: PlaceIntent, in context: Context) async -> NextHourEntry {
        let place = configuration.place.choice
        return NextHourEntry(date: Date(), place: place, forecast: ForecastLoader.cached(place))
    }

    func timeline(for configuration: PlaceIntent, in context: Context) async -> Timeline<NextHourEntry> {
        let place = configuration.place.choice
        let now = Date()
        var forecast = ForecastLoader.cached(place)
        // Refetch unless the app just did.
        if forecast == nil || forecast!.isStale(now: now, after: 10) {
            if let fresh = try? await ForecastLoader().load(place) { forecast = fresh }
        }
        // One entry every 5 minutes so "in 12m" counts down between refreshes.
        let entries = stride(from: 0, through: 60, by: 5).map {
            NextHourEntry(date: now.addingTimeInterval(Double($0) * 60), place: place, forecast: forecast)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(20 * 60)))
    }
}

struct NextHourWidget: Widget {
    let kind = "NextHour"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PlaceIntent.self, provider: NextHourProvider()) { entry in
            NextHourWidgetView(entry: entry)
        }
        .configurationDisplayName("Next hour")
        .description("Rain or snow in the next hour: when, how hard, how long.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall, .systemMedium])
    }
}

struct NextHourWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: NextHourEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: RectangularView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryInline: InlineView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: - Lock screen

private struct RectangularView: View {
    var entry: NextHourEntry

    var body: some View {
        let state = entry.state
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let e = state.event {
                    IntensityMark(intensity: e.peakIntensity, size: 10, monochrome: true)
                }
                Text(NextHourText.compact(state))
                    .font(UFont.display(16))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let e = state.event {
                    Text(Fmt.rate(e.peakRate)).font(UFont.display(14, bold: false))
                } else if let t = entry.forecast?.current?.temperature {
                    Text(Fmt.temp(t)).font(UFont.display(14, bold: false))
                }
            }
            BarsView(bars: entry.bars, height: 20, monochrome: true)
            HStack {
                Text("now")
                Spacer()
                if let e = state.event {
                    Text("\(NextHourText.duration(e)) · \(Fmt.inches(e.displayTotal))")
                } else {
                    Text(entry.forecast?.placeName ?? "Upslope").lineLimit(1)
                }
                Spacer()
                Text(entry.isStale && entry.forecast != nil ? "as of \(Fmt.clock(entry.forecast!.fetchedAt))" : "+60")
            }
            .font(UFont.body(10, weight: .semibold))
            .opacity(0.8)
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

private struct CircularView: View {
    var entry: NextHourEntry

    var body: some View {
        Group {
            switch entry.state {
            case .upcoming(let e, let m):
                Gauge(value: Double(60 - min(m, 60)), in: 0...60) {
                    Image(systemName: PrecipIcon.symbol(e.type))
                } currentValueLabel: {
                    Text(Fmt.shortMinutes(m)).font(UFont.display(18))
                }
                .gaugeStyle(.accessoryCircular)
            case .ongoing(let e, let left):
                Gauge(value: Double(min(left, 60)), in: 0...60) {
                    Image(systemName: PrecipIcon.symbol(e.type))
                } currentValueLabel: {
                    Text(e.continuesPastWindow ? "1h+" : Fmt.shortMinutes(left)).font(UFont.display(18))
                }
                .gaugeStyle(.accessoryCircular)
            case .dry:
                VStack(spacing: 0) {
                    Image(systemName: "sun.max").font(.system(size: 12))
                    Text(entry.forecast?.current.map { Fmt.temp($0.temperature) } ?? "--")
                        .font(UFont.display(20))
                }
            }
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

private struct InlineView: View {
    var entry: NextHourEntry

    var body: some View {
        let state = entry.state
        Label(NextHourText.inline(state), systemImage: PrecipIcon.symbol(state.event?.type ?? .none))
            .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Home screen

private struct SmallView: View {
    var entry: NextHourEntry

    var body: some View {
        let state = entry.state
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let e = state.event { IntensityMark(intensity: e.peakIntensity, size: 11) }
                Text(NextHourText.compact(state))
                    .font(UFont.display(17))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            BarsView(bars: entry.bars, height: 44)
            Group {
                if let e = state.event {
                    Text("\(NextHourText.duration(e)) · \(Fmt.rate(e.peakRate))")
                } else if let c = entry.forecast?.current {
                    Text("\(Fmt.temp(c.temperature)) · feels \(Fmt.temp(c.feelsLike))")
                } else {
                    Text("Open Upslope to load")
                }
            }
            .font(UFont.body(12, weight: .semibold))
            .foregroundStyle(Theme.muted)
            Text(footer)
                .font(UFont.body(11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) { Theme.surface }
    }

    var footer: String {
        guard let f = entry.forecast else { return "" }
        return entry.isStale ? "\(f.placeName) · as of \(Fmt.clock(f.fetchedAt))" : f.placeName
    }
}

private struct MediumView: View {
    var entry: NextHourEntry

    var body: some View {
        let state = entry.state
        let snark = Snark.line(for: state, level: Store.settings.snark)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(NextHourText.headline(state))
                    .font(UFont.display(22))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(entry.forecast?.placeName ?? "")
                    .font(UFont.body(11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Text(snark)
                .font(UFont.body(13))
                .foregroundStyle(Theme.soft)
                .lineLimit(2)
            Spacer(minLength: 0)
            BarsView(bars: entry.bars, height: 36)
            HStack {
                if let e = state.event {
                    stat("Starts", Fmt.clock(e.start))
                    stat("Lasts", NextHourText.duration(e))
                    stat("Peak", Fmt.rate(e.peakRate))
                    stat("Total", Fmt.inches(e.displayTotal))
                } else if let c = entry.forecast?.current {
                    stat("Now", Fmt.temp(c.temperature))
                    stat("Feels", Fmt.temp(c.feelsLike))
                    stat("Wind", "\(Fmt.compass(c.windBearing)) \(Int(c.windSpeed.rounded()))")
                    if let d = entry.forecast?.days.first { stat("High", Fmt.temp(d.high)) }
                }
            }
        }
        .containerBackground(for: .widget) { Theme.surface }
    }

    func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(UFont.body(9, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value).font(UFont.display(16)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
