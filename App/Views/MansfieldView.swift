import SwiftUI
import UpslopeCore

/// Mt. Mansfield seen from Stowe looking west: Forehead, Nose (with towers), Chin, Adam's Apple.
struct MansfieldShape: Shape {
    private static let raw: [(CGFloat, CGFloat)] = [
        (0, 170), (30, 152), (60, 120), (85, 80), (100, 52), (112, 42), (128, 39), (140, 41), (150, 47),
        (160, 44), (165, 43), (172, 47), (182, 44), (190, 46), (200, 38), (212, 26), (222, 17), (230, 21),
        (236, 28), (244, 34), (252, 31), (258, 35), (270, 58), (290, 96), (315, 128), (350, 140)
    ]
    static let points: [CGPoint] = raw.map { CGPoint(x: $0.0, y: $0.1) }
    static let box = CGSize(width: 350, height: 180)

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Self.box.width, sy = rect.height / Self.box.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for pt in Self.points { p.addLine(to: CGPoint(x: rect.minX + pt.x * sx, y: rect.minY + pt.y * sy)) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }

    /// Vertical position (0...1 of the height) for an elevation in feet.
    static func y(forFeet ft: Double) -> CGFloat {
        CGFloat((180 - (ft - 1000) / 3500 * 168) / 180)
    }
}

struct MansfieldView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Mansfield")
                    Text("Mt. Mansfield")
                        .font(UFont.display(44, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.text)
                }

                hero
                ResortReportCard(report: model.report, watchList: model.settings.watchList, snark: model.settings.snark)
                if let m = model.mountain {
                    spots(m)
                    signals(m)
                    weekSnow(m)
                }
                discussion
                Text("Mountain numbers are model forecasts, not the resort's snow report. Resort status is read from stowe.com.")
                    .font(UFont.body(12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await model.refresh(force: true) }
    }

    // MARK: Hero with the ridge and snow line

    var hero: some View {
        let m = model.mountain
        return Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { g in
                    let lineY = MansfieldShape.y(forFeet: m?.snowLineFeet ?? 2400) * g.size.height
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Theme.bg.opacity(0.5))
                        MansfieldShape().fill(Theme.line)
                        MansfieldShape().fill(Theme.text)
                            .mask(alignment: .top) { Rectangle().frame(height: max(0, lineY)) }
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: lineY))
                            p.addLine(to: CGPoint(x: g.size.width, y: lineY))
                        }
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        Text("Snow line ~\(Fmt.feet(m?.snowLineFeet ?? 2400))")
                            .font(UFont.body(12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .offset(x: 8, y: max(4, lineY - 20))
                        Text("Chin 4,393′")
                            .font(UFont.body(10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .position(x: g.size.width * 222 / 350, y: 6)
                    }
                }
                .frame(height: 180)
                .accessibilityElement()
                .accessibilityLabel("Mansfield profile with the snow line near \(Fmt.feet(m?.snowLineFeet ?? 2400))")

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Next 24 hours · upper mountain")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(m.map { Fmt.inchRange($0.upper.snow24h) } ?? "--")
                            .font(UFont.display(60, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.text)
                        Text("vs \(m.map { Fmt.inchRange($0.base.snow24h) } ?? "--") at the base")
                            .font(UFont.body(15))
                            .foregroundStyle(Theme.soft)
                    }
                    if let m {
                        Text(Snark.mountain(upperSnow24h: m.upper.snow24h, baseRain24h: m.base.rain24h,
                                            windHold: m.windHold, level: model.settings.snark,
                                            seed: Int(m.fetchedAt.timeIntervalSince1970 / 21600)))
                            .font(UFont.body(16))
                            .foregroundStyle(Theme.soft)
                        if let by = m.snowLineAtBaseBy, (m.snowLineFeet ?? 0) > Places.mansfieldBaseFeet {
                            Text("Snow line reaches the base around \(Fmt.clock(by)).")
                                .font(UFont.body(14))
                                .foregroundStyle(Theme.muted)
                        }
                    } else {
                        Text("Pull to load the mountain forecast.").font(UFont.body(15)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Upper vs base

    func spots(_ m: MountainForecast) -> some View {
        HStack(spacing: 10) {
            spot("Upper · ~\(Fmt.feet(m.upper.elevationFeet))", m.upper.current)
            spot("Base · ~\(Fmt.feet(m.base.elevationFeet))", m.base.current)
        }
    }

    func spot(_ title: String, _ c: Conditions?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: title)
            Text(c.map { Fmt.temp($0.temperature) } ?? "--").font(UFont.display(34)).foregroundStyle(Theme.text)
            if let c {
                Text("Feels \(Fmt.temp(c.feelsLike))").font(UFont.body(14)).foregroundStyle(Theme.soft)
                Text("\(Fmt.compass(c.windBearing)) \(Int(c.windSpeed.rounded()))\(c.windGust.map { ", gusts \(Int($0.rounded()))" } ?? "") mph")
                    .font(UFont.body(14)).foregroundStyle(Theme.soft)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Upslope + wind hold

    func signals(_ m: MountainForecast) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                signal(icon: "arrow.down.right", title: "Upslope signal: \(m.upslope.label.lowercased())\(m.upslopeStart.map { " from \(Fmt.clock($0))" } ?? "")",
                       text: m.upslope == .none
                        ? "No northwest upslope setup in the next day."
                        : "NW wind slamming into the Greens. Mansfield makes its own snow, and the models usually lowball it.")
                Rectangle().fill(Theme.line).frame(height: 1)
                signal(icon: "wind", title: "Wind-hold risk: \(m.windHold.label.lowercased())\(m.windHoldFrom.map { " after \(Fmt.clock($0))" } ?? "")",
                       text: m.windHold == .low
                        ? "Gusts stay manageable during lift hours. Our guess, not the resort's."
                        : "Gusts to \(Int((m.maxUpperGust ?? 0).rounded())) mph up top. The gondola may sit this one out. Our guess, not the resort's.")
            }
        }
    }

    func signal(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UFont.body(16, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(UFont.body(14)).foregroundStyle(Theme.soft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 7-day upper snow

    func weekSnow(_ m: MountainForecast) -> some View {
        let maxSnow = max(1, m.upperDailySnow.map(\.snow).max() ?? 1)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "Upper mountain snow · 7 days")
                    Spacer()
                    Text("~\(Fmt.inches(m.weekSnowTotal))").font(UFont.display(22)).foregroundStyle(Theme.accent)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(m.upperDailySnow, id: \.date) { d in
                        VStack(spacing: 4) {
                            Text(d.snow >= 0.1 ? Fmt.inches(d.snow) : (d.rain >= 0.05 ? "rain" : "–"))
                                .font(UFont.body(12, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(d.snow >= 4 ? Theme.accent : (d.snow >= 0.1 ? Theme.bar : Theme.line))
                                .frame(height: max(3, CGFloat(d.snow / maxSnow) * 100))
                            Text(Fmt.weekday(d.date, now: model.now))
                                .font(UFont.body(11))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 140, alignment: .bottom)
            }
        }
    }

    // MARK: NWS

    var discussion: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Forecaster's take · NWS Burlington")
            if let d = model.discussion {
                Text(d.synopsis)
                    .font(UFont.body(14))
                    .foregroundStyle(Theme.soft)
                    .lineLimit(8)
                if let issued = d.issued {
                    Text("Issued \(Fmt.clock(issued))").font(UFont.body(12)).foregroundStyle(Theme.muted)
                }
            } else {
                Text("Not loaded yet.").font(UFont.body(14)).foregroundStyle(Theme.muted)
            }
            Link("Read the full discussion", destination: URL(string: "https://forecast.weather.gov/product.php?site=BTV&issuedby=BTV&product=AFD")!)
                .font(UFont.body(14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 32)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

struct ResortReportCard: View {
    var report: ResortReport?
    var watchList: [String]
    var snark: SnarkLevel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Resort report")
                    Spacer()
                    if let r = report { Text("Stowe · \(Fmt.clock(r.fetchedAt))").font(UFont.body(12)).foregroundStyle(Theme.muted) }
                }
                if let r = report, let pct = r.percentOpen {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.percent(pct)).font(UFont.display(52)).foregroundStyle(Theme.accent)
                        Text("of trails open").font(UFont.body(16)).foregroundStyle(Theme.soft)
                    }
                    GeometryReader { g in
                        Capsule().fill(Theme.bg)
                            .overlay(alignment: .leading) { Capsule().fill(Theme.accent).frame(width: g.size.width * pct) }
                    }
                    .frame(height: 8)
                    HStack {
                        number("\(r.trailsOpen)/\(r.trails.count)", "trails")
                        number("\(r.liftsOpen)/\(r.lifts.count)", "lifts")
                        number(r.new24h.map { Fmt.inches($0) } ?? "--", "new, 24 h")
                        number(r.baseDepth.map { Fmt.inches($0) } ?? "--", "base")
                    }
                } else if report != nil {
                    Text("No terrain open yet. Patience.").font(UFont.body(15)).foregroundStyle(Theme.soft)
                } else {
                    Text("Couldn't read stowe.com yet.").font(UFont.body(15)).foregroundStyle(Theme.soft)
                }

                if let r = report, !watchList.isEmpty {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    SectionLabel(text: "Your trails")
                    ForEach(watchList, id: \.self) { name in
                        let s = r.status(of: name)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name).font(UFont.body(17, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(s.map { Snark.trail(name, isOpen: $0.isOpen, level: snark) } ?? "Not in today's report.")
                                    .font(UFont.body(13)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if let s {
                                Text(s.isOpen ? "OPEN" : "CLOSED")
                                    .font(UFont.body(13, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .foregroundStyle(s.isOpen ? Theme.onAccent : Theme.muted)
                                    .background(s.isOpen ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(s.isOpen ? Color.clear : Theme.line))
                            }
                        }
                        .frame(minHeight: 56)
                        .accessibilityElement(children: .combine)
                    }
                    Text("Silent alert when one of these opens. Edit the list in Settings.")
                        .font(UFont.body(12)).foregroundStyle(Theme.muted)
                }

                Link("Open Stowe's report", destination: StoweReportClient.terrainURL)
                    .font(UFont.body(14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 32)
            }
        }
    }

    func number(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(UFont.display(24)).foregroundStyle(Theme.text)
            Text(label).font(UFont.body(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
