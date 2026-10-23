import SwiftUI
import UpslopeCore

struct NowView: View {
    @Environment(AppModel.self) private var model
    @State private var liveActivityError: String?

    var body: some View {
        @Bindable var model = model
        let state = model.nextHour
        let forecast = model.forecast

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Wordmark()
                    Spacer()
                    PlacePicker(place: $model.place)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Next hour · \(forecast?.placeName ?? model.place.label)")
                    Text(NextHourText.headline(state))
                        .font(UFont.display(48, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(Snark.line(for: state, level: model.settings.snark))
                        .font(UFont.body(17))
                        .foregroundStyle(Theme.soft)
                    StaleBanner(forecast: forecast, now: model.now)
                }

                NextHourChart(bars: NextHourBars.bars(forecast?.nextHour, now: model.now), now: model.now,
                              source: forecast?.nextHourSource)

                if let e = state.event {
                    EventStats(state: state, event: e)
                    trackButton(forecast: forecast)
                }

                if let c = forecast?.current {
                    CurrentRow(current: c, today: forecast?.days.first)
                }

                if let days = forecast?.days, !days.isEmpty {
                    SevenDayView(days: days, placeName: forecast?.placeName ?? "", now: model.now)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await model.refresh(force: true) }
    }

    @ViewBuilder
    func trackButton(forecast: Forecast?) -> some View {
        if let forecast, LiveActivityManager.isEnabled {
            Button {
                do {
                    try LiveActivityManager.start(for: forecast)
                    liveActivityError = nil
                } catch {
                    liveActivityError = error.localizedDescription
                }
            } label: {
                Label(LiveActivityManager.isRunning ? "Tracking on your lock screen" : "Track this storm",
                      systemImage: "lock.rectangle.on.rectangle")
                    .font(UFont.body(16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
            if let liveActivityError {
                Text(liveActivityError).font(UFont.body(13)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct NextHourChart: View {
    var bars: [NextHourBar]
    var now: Date
    var source: ForecastSource?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading) {
                        legend(.heavy, "Heavy")
                        Spacer()
                        legend(.moderate, "Mod")
                        Spacer()
                        legend(.light, "Light")
                    }
                    .frame(height: 120)
                    ZStack(alignment: .bottomLeading) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 20)
                            Divider().overlay(Theme.line)
                            Spacer().frame(height: 49)
                            Divider().overlay(Theme.line)
                            Spacer()
                        }
                        BarsView(bars: bars, height: 120)
                        Rectangle().fill(Theme.accent).frame(width: 2, height: 124)
                    }
                    .frame(height: 120)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                HStack {
                    Text("Now").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    ForEach([15, 30, 45, 60], id: \.self) { m in
                        Spacer()
                        Text(Fmt.clock(now.addingTimeInterval(Double(m) * 60)))
                    }
                }
                .font(UFont.body(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 52)
                if source == .openMeteo {
                    Text("15-minute data (add a Pirate Weather key for minute-by-minute)")
                        .font(UFont.body(11))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    func legend(_ i: Intensity, _ label: String) -> some View {
        HStack(spacing: 4) {
            IntensityMark(intensity: i, size: 10)
            Text(label)
        }
        .font(UFont.body(11, weight: .semibold))
        .foregroundStyle(Theme.muted)
    }
}

struct EventStats: View {
    var state: NextHourState
    var event: PrecipEvent

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            switch state {
            case .upcoming(_, let m):
                StatTile(label: "Starts", value: Fmt.clock(event.start), detail: "in \(Fmt.minutes(m))")
            default:
                StatTile(label: "Started", value: Fmt.clock(event.start), detail: "falling now")
            }
            StatTile(label: "Lasts", value: NextHourText.duration(event),
                     detail: event.continuesPastWindow ? "past the hour" : "ends ~\(Fmt.clock(event.end))")
            StatTile(label: "Peak", value: Fmt.rate(event.peakRate),
                     detail: "\(event.peakIntensity.label), ~\(Fmt.clock(event.peakTime))",
                     mark: event.peakIntensity, highlight: true)
            StatTile(label: "Total", value: "~\(Fmt.inches(event.displayTotal))",
                     detail: event.type == .snow ? "snow, this burst" : "\(event.type.noun.lowercased()), this burst")
        }
    }
}

struct CurrentRow: View {
    var current: Conditions
    var today: DayForecast?

    var body: some View {
        HStack {
            item(Fmt.temp(current.temperature), "now")
            Spacer()
            item(Fmt.temp(current.feelsLike), "feels")
            Spacer()
            item("\(Fmt.compass(current.windBearing)) \(Int(current.windSpeed.rounded()))", "mph")
            if let today {
                Spacer()
                item(Fmt.temp(today.high), "high")
            }
        }
        .font(UFont.body(15))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    func item(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.text)
            Text(label).foregroundStyle(Theme.muted)
        }
    }
}

struct SevenDayView: View {
    var days: [DayForecast]
    var placeName: String
    var now: Date

    var body: some View {
        let lo = days.map(\.low).min() ?? 0
        let hi = days.map(\.high).max() ?? 1
        let span = max(1, hi - lo)
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "7 days · \(placeName)")
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(days, id: \.date) { d in
                    HStack(spacing: 10) {
                        Text(Fmt.weekday(d.date, now: now))
                            .font(UFont.body(16, weight: .semibold))
                            .frame(width: 52, alignment: .leading)
                        Image(systemName: PrecipIcon.symbol(d.symbol))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(iconColor(d))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(amount(d)).font(UFont.body(14, weight: .semibold)).foregroundStyle(iconColor(d))
                            Text(Fmt.percent(d.precipChance)).font(UFont.body(12)).foregroundStyle(Theme.muted)
                        }
                        .frame(width: 64, alignment: .leading)
                        Text(Fmt.temp(d.low)).foregroundStyle(Theme.muted).frame(width: 32, alignment: .trailing)
                        GeometryReader { g in
                            Capsule().fill(Theme.bg)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.accent)
                                        .frame(width: max(6, g.size.width * (d.high - d.low) / span))
                                        .offset(x: g.size.width * (d.low - lo) / span)
                                }
                        }
                        .frame(height: 6)
                        Text(Fmt.temp(d.high)).fontWeight(.semibold).frame(width: 32, alignment: .leading)
                    }
                    .font(UFont.body(15))
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 52)
                    .padding(.horizontal, 16)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    func amount(_ d: DayForecast) -> String {
        if d.snowInches >= 0.1 { return "\(Fmt.inchRange(d.snowInches)) snow" }
        if d.rainInches >= 0.01 { return Fmt.inches(d.rainInches) }
        return "Dry"
    }

    func iconColor(_ d: DayForecast) -> Color {
        switch d.symbol {
        case .snow: return Theme.snow
        case .rain, .storm: return Theme.rain
        case .mix: return Theme.mix
        case .sun: return Theme.accent
        default: return Theme.muted
        }
    }
}
