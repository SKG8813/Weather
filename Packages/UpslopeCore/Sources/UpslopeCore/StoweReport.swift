import Foundation

public struct TrailStatus: Codable, Sendable, Equatable {
    public var name: String
    public var isOpen: Bool
}

public struct ResortReport: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var reportDate: String?
    public var trails: [TrailStatus]
    public var lifts: [TrailStatus]
    public var new24h: Double?
    public var new7d: Double?
    public var baseDepth: Double?

    public var trailsOpen: Int { trails.filter(\.isOpen).count }
    public var liftsOpen: Int { lifts.filter(\.isOpen).count }
    /// Share of trails open, 0...1. nil before the season.
    public var percentOpen: Double? { trails.isEmpty ? nil : Double(trailsOpen) / Double(trails.count) }

    public func status(of name: String) -> TrailStatus? {
        let key = ResortReport.normalize(name)
        return (trails + lifts).first { ResortReport.normalize($0.name) == key }
            ?? (trails + lifts).first { ResortReport.normalize($0.name).hasPrefix(key) }
    }

    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

/// Reads Stowe's public terrain and snow report pages on stowe.com.
///
/// There is no official API. Vail Resorts pages embed JSON in script tags as
/// `FR.TerrainStatusFeed = {...};` (lifts with "Status": "Open"/"Closed"/…, trails
/// nested under keys mentioning runs or trails). The snow page embeds a similar object.
/// The parser is deliberately loose because the markup can change without notice.
public struct StoweReportClient: Sendable {
    public var http: HTTPClient
    public static let terrainURL = URL(string: "https://www.stowe.com/the-mountain/mountain-conditions/terrain-and-lift-status.aspx")!
    public static let snowURL = URL(string: "https://www.stowe.com/the-mountain/mountain-conditions/snow-and-weather-report.aspx")!

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    static let headers = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Upslope/1.0",
        "Accept": "text/html"
    ]

    public func fetch(now: Date = Date()) async throws -> ResortReport {
        async let terrain = http.get(Self.terrainURL, headers: Self.headers)
        async let snow: Data? = { try? await http.get(Self.snowURL, headers: Self.headers) }()
        let t = try await terrain
        let s = await snow
        return try StoweReportParser.parse(terrainHTML: String(decoding: t, as: UTF8.self),
                                           snowHTML: s.map { String(decoding: $0, as: UTF8.self) },
                                           now: now)
    }
}

public enum StoweReportParser {
    public enum ParseError: Error { case noTerrainFeed }

    public static func parse(terrainHTML: String, snowHTML: String?, now: Date) throws -> ResortReport {
        let feeds = jsonObjects(after: "FR.TerrainStatusFeed", in: terrainHTML)
        // Vail ships two near-identical feeds; prefer the one with string statuses / ISO date.
        guard let feed = feeds.first(where: { !(($0["Date"] as? String) ?? "").contains("Date(") }) ?? feeds.first else {
            throw ParseError.noTerrainFeed
        }

        let lifts = (feed["Lifts"] as? [[String: Any]] ?? []).compactMap(status)
        var trails: [TrailStatus] = []
        collectTrails(feed, into: &trails)

        var report = ResortReport(fetchedAt: now, reportDate: feed["Date"] as? String, trails: dedupe(trails), lifts: lifts)

        if let snowHTML {
            let snowObjects = jsonObjects(matching: "snow", in: snowHTML)
            for obj in snowObjects {
                report.new24h = report.new24h ?? inches(obj, keys: ["TwentyFourHourSnowfall", "24HourSnowfall", "Last24Hours"])
                report.new7d = report.new7d ?? inches(obj, keys: ["SevenDaySnowfall", "Last7Days"])
                report.baseDepth = report.baseDepth ?? inches(obj, keys: ["BaseDepth", "Base"])
            }
        }
        return report
    }

    // MARK: - Trails

    /// Any array under a key mentioning runs or trails holds trail records.
    static func collectTrails(_ value: Any, into out: inout [TrailStatus]) {
        if let dict = value as? [String: Any] {
            for (k, v) in dict where k != "Lifts" {
                let lower = k.lowercased()
                if lower.contains("run") || lower.contains("trail"), let arr = v as? [Any] {
                    for item in arr {
                        if let d = item as? [String: Any], let s = status(d) { out.append(s) }
                    }
                }
                collectTrails(v, into: &out)
            }
        } else if let arr = value as? [Any] {
            for v in arr { collectTrails(v, into: &out) }
        }
    }

    static func status(_ d: [String: Any]) -> TrailStatus? {
        guard let name = (d["Name"] ?? d["name"]) as? String, !name.isEmpty else { return nil }
        if let b = (d["IsOpen"] ?? d["isOpen"]) as? Bool { return TrailStatus(name: name, isOpen: b) }
        if let s = (d["Status"] ?? d["status"]) as? String {
            let v = s.lowercased()
            return TrailStatus(name: name, isOpen: v == "open" || v == "onhold" || v == "on hold")
        }
        if let n = (d["Status"] ?? d["status"]) as? NSNumber {
            return TrailStatus(name: name, isOpen: n.intValue == 1)
        }
        return nil
    }

    static func dedupe(_ list: [TrailStatus]) -> [TrailStatus] {
        var seen = Set<String>()
        return list.filter { seen.insert(ResortReport.normalize($0.name)).inserted }
    }

    // MARK: - Snow numbers

    static func inches(_ obj: [String: Any], keys: [String]) -> Double? {
        for (k, v) in obj {
            if keys.contains(where: { $0.caseInsensitiveCompare(k) == .orderedSame }) {
                if let d = v as? [String: Any] {
                    if let x = number(d["Inches"] ?? d["inches"]) { return x }
                } else if let x = number(v) {
                    return x
                }
            }
            if let d = v as? [String: Any], let x = inches(d, keys: keys) { return x }
        }
        return nil
    }

    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "\" ″in"))) }
        return nil
    }

    // MARK: - JSON extraction from HTML

    /// Every `{...}` assigned right after `marker` (e.g. `FR.TerrainStatusFeed = {...}`).
    static func jsonObjects(after marker: String, in html: String) -> [[String: Any]] {
        var results: [[String: Any]] = []
        var search = html.startIndex..<html.endIndex
        while let r = html.range(of: marker, range: search) {
            if let obj = object(startingAfter: r.upperBound, in: html) { results.append(obj) }
            search = r.upperBound..<html.endIndex
        }
        return results
    }

    /// Objects assigned to any `FR.<name> =` whose name contains `fragment`.
    static func jsonObjects(matching fragment: String, in html: String) -> [[String: Any]] {
        var results: [[String: Any]] = []
        var search = html.startIndex..<html.endIndex
        while let r = html.range(of: "FR.", range: search) {
            let nameEnd = html[r.upperBound...].firstIndex(where: { !($0.isLetter || $0.isNumber || $0 == "_") }) ?? html.endIndex
            let name = html[r.upperBound..<nameEnd]
            if name.lowercased().contains(fragment), let obj = object(startingAfter: nameEnd, in: html) {
                results.append(obj)
            }
            search = nameEnd..<html.endIndex
        }
        return results
    }

    /// Finds `= {` after `index` and decodes the balanced object.
    static func object(startingAfter index: String.Index, in html: String) -> [String: Any]? {
        var i = index
        // Expect optional spaces, "=", optional spaces, "{".
        while i < html.endIndex, html[i] == " " { i = html.index(after: i) }
        guard i < html.endIndex, html[i] == "=" else { return nil }
        i = html.index(after: i)
        while i < html.endIndex, html[i].isWhitespace { i = html.index(after: i) }
        guard i < html.endIndex, html[i] == "{" else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var j = i
        while j < html.endIndex {
            let c = html[j]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let json = html[i...j]
                    return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
                }
            }
            j = html.index(after: j)
        }
        return nil
    }
}

/// Watches chosen trails and lifts and reports which ones just opened.
public enum TrailWatch {
    public static let defaultWatchList = ["Upper National", "Goat", "Starr Glades"]

    /// Names that are open now but were not open last time.
    public static func justOpened(previous: [String: Bool], report: ResortReport, watch: [String]) -> [String] {
        watch.compactMap { name in
            guard let s = report.status(of: name), s.isOpen else { return nil }
            return previous[name] == false ? name : nil
        }
    }

    public static func snapshot(_ report: ResortReport, watch: [String]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for name in watch {
            if let s = report.status(of: name) { out[name] = s.isOpen }
        }
        return out
    }
}
