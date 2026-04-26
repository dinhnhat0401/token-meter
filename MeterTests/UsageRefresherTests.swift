import XCTest
@testable import Meter

@MainActor
final class UsageRefresherTests: XCTestCase {
    private func makeSnapshot(five: Double = 0.4, seven: Double = 0.2) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: UsageWindow(utilization: five, resetsAt: nil),
            sevenDay: UsageWindow(utilization: seven, resetsAt: nil),
            source: .api,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func test_refresh_apiSuccess_setsOk() async {
        let snapshot = makeSnapshot()
        let refresher = UsageRefresher(
            keychain: StubKeychain(result: .success("tok")),
            api: StubAPI(stub: .success(snapshot)),
            aggregator: StubAggregator(totalTokens: 0, recordCount: 0),
            projectsDirectory: URL(fileURLWithPath: "/tmp/nonexistent"),
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            autoStart: false
        )
        await refresher.refresh()

        if case .ok(let s) = refresher.state {
            XCTAssertEqual(s, snapshot)
        } else {
            XCTFail("expected .ok, got \(refresher.state)")
        }
    }

    func test_refresh_missingKeychainItem_setsMissingToken() async {
        let refresher = UsageRefresher(
            keychain: StubKeychain(result: .failure(KeychainError.itemNotFound)),
            api: StubAPI(stub: .success(makeSnapshot())),
            aggregator: StubAggregator(totalTokens: 0, recordCount: 0),
            projectsDirectory: URL(fileURLWithPath: "/tmp/nonexistent"),
            autoStart: false
        )
        await refresher.refresh()
        XCTAssertEqual(refresher.state, .missingToken)
    }

    func test_refresh_otherKeychainError_setsError() async {
        let refresher = UsageRefresher(
            keychain: StubKeychain(result: .failure(KeychainError.unhandled(-1))),
            api: StubAPI(stub: .success(makeSnapshot())),
            aggregator: StubAggregator(totalTokens: 0, recordCount: 0),
            projectsDirectory: URL(fileURLWithPath: "/tmp/nonexistent"),
            autoStart: false
        )
        await refresher.refresh()
        guard case .error = refresher.state else {
            return XCTFail("expected .error, got \(refresher.state)")
        }
    }

    func test_refresh_apiUnauthorized_fallsBackToEstimate() async {
        let refresher = UsageRefresher(
            keychain: StubKeychain(result: .success("tok")),
            api: StubAPI(stub: .failure(AnthropicAPIError.unauthorized)),
            aggregator: StubAggregator(totalTokens: 12345, recordCount: 7),
            projectsDirectory: URL(fileURLWithPath: "/tmp/nonexistent"),
            autoStart: false
        )
        await refresher.refresh()

        guard case .estimated(let snapshot, let underlying) = refresher.state else {
            return XCTFail("expected .estimated, got \(refresher.state)")
        }
        XCTAssertEqual(snapshot.source, .estimated)
        XCTAssertEqual(snapshot.estimatedFiveHourTokens, 12345)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.sevenDay)
        XCTAssertTrue(underlying.contains("401"))
    }

    func test_refresh_apiServerError_fallsBackWithCodeInMessage() async {
        let refresher = UsageRefresher(
            keychain: StubKeychain(result: .success("tok")),
            api: StubAPI(stub: .failure(AnthropicAPIError.server(502))),
            aggregator: StubAggregator(totalTokens: 0, recordCount: 0),
            projectsDirectory: URL(fileURLWithPath: "/tmp/nonexistent"),
            autoStart: false
        )
        await refresher.refresh()
        guard case .estimated(_, let underlying) = refresher.state else {
            return XCTFail("expected .estimated, got \(refresher.state)")
        }
        XCTAssertTrue(underlying.contains("502"))
    }

    func test_refresh_recoverFromEstimatedOnNextSuccess() async {
        let stubAPI = StubAPI(stub: .failure(AnthropicAPIError.unauthorized))
        let refresher = UsageRefresher(
            keychain: StubKeychain(result: .success("tok")),
            api: stubAPI,
            aggregator: StubAggregator(totalTokens: 100, recordCount: 1),
            projectsDirectory: URL(fileURLWithPath: "/tmp/nonexistent"),
            autoStart: false
        )
        await refresher.refresh()
        guard case .estimated = refresher.state else {
            return XCTFail("expected initial .estimated")
        }

        let goodSnapshot = makeSnapshot()
        stubAPI.stub = .success(goodSnapshot)
        await refresher.refresh()

        guard case .ok(let s) = refresher.state else {
            return XCTFail("expected .ok after recovery")
        }
        XCTAssertEqual(s.source, .api)
        XCTAssertEqual(s, goodSnapshot)
    }
}
