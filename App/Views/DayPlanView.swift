import SwiftUI
import UpslopeCore

/// Tap a day in the 7-day list: a plan for the day in three parts, not an hourly list.
struct DayPlanView: View {
    var day: DayForecast
    var forecast: Forecast
    var place: PlaceChoice
    var mountain: MountainForecast?
    var snark: SnarkLevel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tz = forecast.timeZone
        let plan = DayPlanner.plan(for: day, hours: forecast.hours ?? [], timeZone: tz)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "\(Self.longDate(day.date, tz)) · \(forecast.placeName)")
                        Text(plan.summary)
                            .font(UFont.display(30, relativeTo: .title))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let c = plan.changeover {
                            Label(c, systemImage: "arrow.triangle.swap")
                                .font(UFont.body(15, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    if !plan.parts.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(plan.parts, id: \.name) { PartCard(part: $0, timeZone: tz) }
                        }
                    }

                    if !plan.windows.isEmpty {
                        WetStrip(plan: plan, timeZone: tz)
                    }

                    numbers(plan, tz: tz)

                    if let verdict = skiVerdict(tz: tz) {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel(text: "Mansfield")
                                Text(verdict).font(UFont.body(16, weight: .medium)).foregroundStyle(Theme.text)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Fmt.weekday(day.date, timeZone: tz))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    func numbers(_ plan: DayPlan, tz: TimeZone) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(label: "High", value: Fmt.temp(plan.high), detail: plan.highAt.map { "around \(Fmt.hour($0, timeZone: tz))" })
            StatTile(label: "Low", value: Fmt.temp(plan.low), detail: plan.lowAt.map { "around \(Fmt.hour($0, timeZone: tz))" })
            if let feels = plan.feelsLikeLow {
                StatTile(label: "Feels like", value: Fmt.temp(feels), detail: "at its coldest")
            }
            if let gust = plan.maxGust {
                StatTile(label: "Gusts", value: "\(Int(gust.rounded())) mph", detail: "strongest")
            }
            StatTile(label: "Snow", value: plan.snowTotal >= 0.1 ? Fmt.inchRange(plan.snowTotal) : "None",
                     detail: plan.snowTotal >= 0.1 ? "total" : nil)
            StatTile(label: "Rain", value: plan.rainTotal >= 0.01 ? Fmt.inches(plan.rainTotal) : "None",
                     detail: plan.rainTotal >= 0.01 ? "total" : nil)
            if let rise = plan.sunrise, let set = plan.sunset {
                StatTile(label: "Sunrise", value: Fmt.clock(rise, timeZone: tz), detail: "am")
                StatTile(label: "Sunset", value: Fmt.clock(set, timeZone: tz), detail: "pm")
            }
        }
    }

    /// Only for Stowe, when the Mansfield forecast covers this day.
    func skiVerdict(tz: TimeZone) -> String? {
        guard place == .stowe, let m = mountain else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let upper = m.upperDailySnow.first(where: { cal.isDate($0.date, inSameDayAs: day.date) }) else { return nil }
        let isToday = cal.isDate(day.date, inSameDayAs: Date())
        return DayPlanner.skiVerdict(upperSnow: upper.snow, upperRain: upper.rain,
                                     windHold: isToday ? m.windHold : nil, windFrom: isToday ? m.windHoldFrom : nil,
                                     timeZone: tz)
    }

    static func longDate(_ d: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: d)
    }
}

/// Morning, afternoon or night at a glance.
private struct PartCard: View {
    var part: DayPlan.Part
    var timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: part.name.rawValue)
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(height: 28)
            Text(Fmt.temp(part.temperature))
                .font(UFont.display(30))
                .foregroundStyle(Theme.text)
            Text(part.name == .night ? "low" : "high")
                .font(UFont.body(11))
                .foregroundStyle(Theme.muted)
            Text(precip)
                .font(UFont.body(14, weight: .semibold))
                .foregroundStyle(part.isDry ? Theme.muted : color)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if !part.isDry {
                Text("\(Fmt.percent(part.chance)) chance").font(UFont.body(12)).foregroundStyle(Theme.muted)
            }
            Text("\(Fmt.compass(part.windBearing)) \(Int(part.wind.rounded())) mph")
                .font(UFont.body(12))
                .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    var precip: String {
        if part.snow >= 0.1 && part.rain >= 0.02 { return "\(Fmt.inchRange(part.snow)) snow + rain" }
        if part.snow >= 0.1 { return "\(Fmt.inchRange(part.snow)) snow" }
        if part.rain >= 0.02 { return "\(Fmt.inches(part.rain)) rain" }
        return part.chance >= 0.3 ? "Mostly dry" : "Dry"
    }

    var icon: String {
        if part.name == .night {
            switch part.symbol {
            case .sun: return "moon.stars"
            case .partly: return "cloud.moon"
            default: break
            }
        }
        return PrecipIcon.symbol(part.symbol)
    }

    var color: Color {
        switch part.symbol {
        case .snow: return Theme.snow
        case .rain, .storm: return Theme.rain
        case .mix: return Theme.mix
        case .sun: return part.name == .night ? Theme.soft : Theme.accent
        default: return Theme.muted
        }
    }
}

/// 6 am to 6 am, with the wet windows shaded. Shows when, without listing hours.
private struct WetStrip: View {
    var plan: DayPlan
    var timeZone: TimeZone

    var body: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: plan.date).addingTimeInterval(6 * 3600)
        let span: TimeInterval = 24 * 3600

        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "When it's wet")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.bg)
                        ForEach(plan.windows, id: \.start) { w in
                            let x = max(0, w.start.timeIntervalSince(start) / span) * g.size.width
                            let width = max(6, min(w.end, start.addingTimeInterval(span)).timeIntervalSince(max(w.start, start)) / span * g.size.width)
                            Capsule().fill(Theme.color(for: w.type)).frame(width: width).offset(x: x)
                        }
                    }
                }
                .frame(height: 14)
                HStack {
                    Text("6a"); Spacer(); Text("12p"); Spacer(); Text("6p"); Spacer(); Text("12a"); Spacer(); Text("6a")
                }
                .font(UFont.body(11, weight: .medium))
                .foregroundStyle(Theme.muted)
                ForEach(plan.windows, id: \.start) { w in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.color(for: w.type)).frame(width: 8, height: 8)
                        Text("\(w.type.noun) \(Fmt.hourRange(w.start, w.end, timeZone: timeZone)) · heaviest ~\(Fmt.hour(w.peak, timeZone: timeZone))")
                            .font(UFont.body(14, weight: .medium))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
