import XCTest
@testable import Meter

final class AnthropicAPIClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.anthropic.com")!

    // MARK: - Decoding

    func test_decode_okFixture_normalizesPercentageToFraction() throws {
        let data = TestFixtures.data(named: "usage_response_ok.json")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try AnthropicAPIClient.decode(data: data, capturedAt: now)

        XCTAssertEqual(snapshot.source, .api)
        XCTAssertEqual(snapshot.capturedAt, now)
        XCTAssertEqual(snapshot.fiveHour?.utilization ?? 0, 0.61, accuracy: 0.0001)
        XCTAssertEqual(snapshot.sevenDay?.utilization ?? 0, 0.46, accuracy: 0.0001)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNotNil(snapshot.sevenDay?.resetsAt)
    }

    func test_decode_partialFixture_acceptsMissingSevenDayWindow() throws {
        let data = TestFixtures.data(named: "usage_response_partial.json")
        let snapshot = try AnthropicAPIClient.decode(data: data, capturedAt: Date())
        XCTAssertNotNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.sevenDay)
        XCTAssertNil(snapshot.fiveHour?.resetsAt)
        XCTAssertEqual(snapshot.fiveHour?.utilization ?? 0, 0.995, accuracy: 0.0001)
    }

    func test_decode_malformedFixture_throws() {
        let data = TestFixtures.data(named: "usage_response_malformed.json")
        XCTAssertThrowsError(try AnthropicAPIClient.decode(data: data, capturedAt: Date()))
    }

    func test_decode_emptyObject_throws() {
        XCTAssertThrowsError(try AnthropicAPIClient.decode(data: Data("{}".utf8), capturedAt: Date()))
    }

    func test_parseISODate_handlesMicrosecondPrecision() {
        let date = AnthropicAPIClient.parseISODate("2026-04-26T05:20:00.413009+00:00")
        XCTAssertNotNil(date)
    }

    func test_parseISODate_handlesNoFractionalSeconds() {
        let date = AnthropicAPIClient.parseISODate("2026-04-26T05:20:00Z")
        XCTAssertNotNil(date)
    }

    func test_parseISODate_returnsNilForGarbage() {
        XCTAssertNil(AnthropicAPIClient.parseISODate("not-a-date"))
    }

    // MARK: - Network

    func test_fetchUsage_success_returnsSnapshot() async throws {
        let payload = TestFixtures.data(named: "usage_response_ok.json")
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            (payload, makeHTTPResponse(status: 200))
        }
        let snapshot = try await client.fetchUsage(token: "tok")
        XCTAssertEqual(snapshot.source, .api)
        XCTAssertEqual(snapshot.fiveHour?.percent, 61)
    }

    func test_fetchUsage_sendsBearerAndBetaHeader() async throws {
        let payload = TestFixtures.data(named: "usage_response_ok.json")
        var captured: URLRequest?
        let client = AnthropicAPIClient(baseURL: baseURL) { request in
            captured = request
            return (payload, makeHTTPResponse(status: 200))
        }
        _ = try await client.fetchUsage(token: "my-secret-token")

        XCTAssertEqual(
            captured?.value(forHTTPHeaderField: "Authorization"),
            "Bearer my-secret-token"
        )
        XCTAssertEqual(
            captured?.value(forHTTPHeaderField: "anthropic-beta"),
            "oauth-2025-04-20"
        )
        XCTAssertEqual(captured?.url?.path, "/api/oauth/usage")
        XCTAssertEqual(captured?.httpMethod, "GET")
    }

    func test_fetchUsage_401_throwsUnauthorized() async {
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            (Data("{}".utf8), makeHTTPResponse(status: 401))
        }
        await XCTAssertThrowsErrorAsync(try await client.fetchUsage(token: "tok")) { error in
            XCTAssertEqual(error as? AnthropicAPIError, .unauthorized)
        }
    }

    func test_fetchUsage_403_throwsUnauthorized() async {
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            (Data(), makeHTTPResponse(status: 403))
        }
        await XCTAssertThrowsErrorAsync(try await client.fetchUsage(token: "tok")) { error in
            XCTAssertEqual(error as? AnthropicAPIError, .unauthorized)
        }
    }

    func test_fetchUsage_429_extractsRetryAfter() async {
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            (Data(), makeHTTPResponse(status: 429, headers: ["Retry-After": "42"]))
        }
        await XCTAssertThrowsErrorAsync(try await client.fetchUsage(token: "tok")) { error in
            XCTAssertEqual(error as? AnthropicAPIError, .rateLimited(retryAfter: 42))
        }
    }

    func test_fetchUsage_500_throwsServer() async {
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            (Data(), makeHTTPResponse(status: 503))
        }
        await XCTAssertThrowsErrorAsync(try await client.fetchUsage(token: "tok")) { error in
            XCTAssertEqual(error as? AnthropicAPIError, .server(503))
        }
    }

    func test_fetchUsage_malformedSuccessBody_throwsMalformed() async {
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            (Data("garbage".utf8), makeHTTPResponse(status: 200))
        }
        await XCTAssertThrowsErrorAsync(try await client.fetchUsage(token: "tok")) { error in
            XCTAssertEqual(error as? AnthropicAPIError, .malformedResponse)
        }
    }

    func test_fetchUsage_transportError_throwsTransport() async {
        struct Boom: Error {}
        let client = AnthropicAPIClient(baseURL: baseURL) { _ in
            throw Boom()
        }
        await XCTAssertThrowsErrorAsync(try await client.fetchUsage(token: "tok")) { error in
            guard case .transport = error as? AnthropicAPIError else {
                XCTFail("expected .transport, got \(error)")
                return
            }
        }
    }
}

// MARK: - async throws helper

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message.isEmpty ? "Expected error" : message, file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
