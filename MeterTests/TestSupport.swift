import Foundation
@testable import Meter

enum TestFixtures {
    static func data(named name: String, bundle: Bundle = Bundle(for: FixtureLocator.self)) -> Data {
        // Files live under MeterTests/Fixtures/*. xcodegen flattens them
        // alongside the test bundle root, so look there first then fall back.
        let candidates = [
            bundle.url(forResource: name, withExtension: nil),
            bundle.url(
                forResource: (name as NSString).deletingPathExtension,
                withExtension: (name as NSString).pathExtension
            ),
            bundle.url(
                forResource: (name as NSString).deletingPathExtension,
                withExtension: (name as NSString).pathExtension,
                subdirectory: "Fixtures"
            ),
        ].compactMap { $0 }

        for url in candidates {
            if let data = try? Data(contentsOf: url) { return data }
        }
        fatalError("Missing test fixture: \(name)")
    }

    static func string(named name: String) -> String {
        guard let s = String(data: data(named: name), encoding: .utf8) else {
            fatalError("Fixture not utf8: \(name)")
        }
        return s
    }
}

/// Marker class used to anchor `Bundle(for:)` to the test bundle.
final class FixtureLocator {}

struct StubKeychain: KeychainReading {
    let result: Result<String, Error>
    func readClaudeOAuthToken() throws -> String { try result.get() }
}

final class StubAPI: AnthropicUsageFetching, @unchecked Sendable {
    var stub: Result<UsageSnapshot, Error>
    private(set) var calls: [String] = []

    init(stub: Result<UsageSnapshot, Error>) { self.stub = stub }

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        calls.append(token)
        return try stub.get()
    }
}

struct StubAggregator: JSONLAggregating {
    let totalTokens: Int
    let recordCount: Int
    func aggregateRollingWindow(
        endingAt now: Date,
        duration: TimeInterval,
        rootDirectory: URL
    ) -> (totalTokens: Int, recordCount: Int) {
        (totalTokens, recordCount)
    }
}

func makeHTTPResponse(
    url: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
    status: Int,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}
