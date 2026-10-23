import Foundation

/// The latest Area Forecast Discussion from NWS Burlington (BTV).
public struct ForecastDiscussion: Codable, Sendable, Equatable {
    public var issued: Date?
    public var synopsis: String
    public var fullText: String
    public var url: URL
}

public struct NWSClient: Sendable {
    public var http: HTTPClient
    public var office: String

    public init(office: String = "BTV", http: HTTPClient = URLSessionHTTPClient()) {
        self.office = office
        self.http = http
    }

    static let headers = ["User-Agent": UserAgent.value, "Accept": "application/ld+json"]

    public func latestDiscussion() async throws -> ForecastDiscussion {
        let listURL = URL(string: "https://api.weather.gov/products/types/AFD/locations/\(office)")!
        let list = try await http.get(listURL, headers: Self.headers)
        guard let id = try Self.latestID(list) else { throw HTTPError.badResponse }
        let productURL = URL(string: "https://api.weather.gov/products/\(id)")!
        let product = try await http.get(productURL, headers: Self.headers)
        return try Self.parseProduct(product, url: productURL)
    }

    static func latestID(_ data: Data) throws -> String? {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let graph = root?["@graph"] as? [[String: Any]]
        return graph?.first?["id"] as? String
    }

    static func parseProduct(_ data: Data, url: URL) throws -> ForecastDiscussion {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["productText"] as? String else { throw HTTPError.badResponse }
        let issued = (root["issuanceTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return ForecastDiscussion(issued: issued, synopsis: synopsis(from: text), fullText: text, url: url)
    }

    /// Section headers to try, in order. BTV currently leads with KEY MESSAGES;
    /// older discussions use SYNOPSIS.
    static let summarySections = [".KEY MESSAGES...", ".SYNOPSIS...", ".DISCUSSION..."]

    /// The summary section, unwrapped into paragraphs (one per numbered message).
    static func synopsis(from text: String) -> String {
        var section: Substring?
        for header in summarySections {
            if let r = text.range(of: header) {
                let rest = text[r.upperBound...]
                let end = rest.range(of: "&&")?.lowerBound ?? rest.endIndex
                section = rest[..<end]
                break
            }
        }
        let body = section ?? Substring(text.prefix(800))

        var paragraphs: [String] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
            current = []
        }
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("As of") || line.hasPrefix("Issued at") { continue }
            current.append(line)
        }
        flush()
        return paragraphs.joined(separator: "\n")
    }
}
