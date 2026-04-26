import Foundation

public protocol AnthropicUsageFetching: Sendable {
    func fetchUsage(token: String) async throws -> UsageSnapshot
}

public enum AnthropicAPIError: Error, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    case malformedResponse
    case transport(String)
}

public struct AnthropicAPIClient: AnthropicUsageFetching {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let dataLoader: DataLoader
    private let now: @Sendable () -> Date

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.dataLoader = { request in try await session.data(for: request) }
        self.now = { Date() }
    }

    /// Test-only init: stub the network without subclassing `URLSession`.
    public init(
        baseURL: URL,
        dataLoader: @escaping DataLoader,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.dataLoader = dataLoader
        self.now = now
    }

    public func fetchUsage(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/oauth/usage"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Required: without this header the endpoint rejects OAuth tokens.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch {
            throw AnthropicAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicAPIError.malformedResponse
        }

        switch http.statusCode {
        case 200:
            return try Self.decode(data: data, capturedAt: now())
        case 401, 403:
            throw AnthropicAPIError.unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw AnthropicAPIError.rateLimited(retryAfter: retry)
        case 500...599:
            throw AnthropicAPIError.server(http.statusCode)
        default:
            throw AnthropicAPIError.server(http.statusCode)
        }
    }

    static func decode(data: Data, capturedAt: Date) throws -> UsageSnapshot {
        struct WirePayload: Decodable {
            struct Window: Decodable {
                let utilization: Double
                let resets_at: String?
            }
            let five_hour: Window?
            let seven_day: Window?
        }

        guard let payload = try? JSONDecoder().decode(WirePayload.self, from: data) else {
            throw AnthropicAPIError.malformedResponse
        }

        guard payload.five_hour != nil || payload.seven_day != nil else {
            throw AnthropicAPIError.malformedResponse
        }

        // Endpoint emits utilization on a 0–100 scale; normalize to 0–1.
        func mapWindow(_ w: WirePayload.Window?) -> UsageWindow? {
            guard let w = w else { return nil }
            return UsageWindow(
                utilization: w.utilization / 100.0,
                resetsAt: w.resets_at.flatMap(parseISODate(_:))
            )
        }

        return UsageSnapshot(
            fiveHour: mapWindow(payload.five_hour),
            sevenDay: mapWindow(payload.seven_day),
            source: .api,
            capturedAt: capturedAt
        )
    }

    /// Endpoint emits microsecond precision (e.g. `2026-04-26T05:20:00.413009+00:00`).
    /// `ISO8601DateFormatter.withFractionalSeconds` only handles 3-digit ms, so
    /// strip any fractional part and parse what's left.
    static func parseISODate(_ s: String) -> Date? {
        let stripped = s.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: stripped)
    }
}
