import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPError: Error, Equatable {
    case status(Int)
    case badResponse
    case missingKey
}

/// Small seam so clients can be tested with canned responses.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw HTTPError.status(http.statusCode) }
        return data
    }
}

/// Identifies us politely to free APIs (NWS asks for this).
public enum UserAgent {
    public static let value = "Upslope/1.0 (personal weather app)"
}
