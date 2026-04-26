import XCTest
@testable import Meter

final class JSONLParserTests: XCTestCase {
    func test_parse_sampleFixture_skipsMalformedAndEmptyUsage() {
        let parser = JSONLParser()
        let content = TestFixtures.string(named: "projects_sample.jsonl")
        let records = parser.parse(content: content)

        // 5 lines have parseable JSON; only 2 carry non-empty `message.usage`.
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].totalTokens, 10 + 20 + 100 + 200)
        XCTAssertEqual(records[1].totalTokens, 5 + 15 + 0 + 50)
    }

    func test_parse_emptyContent_returnsEmpty() {
        XCTAssertTrue(JSONLParser().parse(content: "").isEmpty)
    }

    func test_parse_singleTurn_returnsOneRecord() {
        let line = #"{"type":"assistant","timestamp":"2026-04-26T09:00:00Z","message":{"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4}}}"#
        let records = JSONLParser().parse(content: line)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].totalTokens, 10)
    }

    func test_parse_skipsZeroTokenTurns() {
        let line = #"{"type":"assistant","timestamp":"2026-04-26T09:00:00Z","message":{"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        XCTAssertTrue(JSONLParser().parse(content: line).isEmpty)
    }

    func test_parse_skipsTurnWithoutUsage() {
        let line = #"{"type":"assistant","timestamp":"2026-04-26T09:00:00Z","message":{"role":"assistant"}}"#
        XCTAssertTrue(JSONLParser().parse(content: line).isEmpty)
    }

    func test_aggregateRollingWindow_filtersByCutoff() throws {
        // Write the two fixtures into a temp directory laid out like
        // `~/.claude/projects/<slug>/*.jsonl`.
        let tempRoot = try makeTempProjectsDir(
            files: [
                "proj-a/recent.jsonl": TestFixtures.string(named: "projects_sample.jsonl"),
                "proj-b/old.jsonl": TestFixtures.string(named: "projects_old.jsonl"),
            ]
        )
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Fixture timestamps: recent ~ 2026-04-26 09–10 UTC, old = 2026-04-25 08:00 UTC.
        // Anchor "now" at 2026-04-26 11:00 UTC; the rolling 5-hour window then
        // includes only the recent file.
        let now = ISO8601DateFormatter().date(from: "2026-04-26T11:00:00Z")!
        let agg = JSONLParser().aggregateRollingWindow(
            endingAt: now,
            duration: 5 * 3600,
            rootDirectory: tempRoot
        )
        // 2 valid records in projects_sample.jsonl: 330 + 70 = 400 tokens.
        XCTAssertEqual(agg.recordCount, 2)
        XCTAssertEqual(agg.totalTokens, 400)
    }

    func test_aggregateRollingWindow_emptyDirectory_returnsZero() throws {
        let tempRoot = try makeTempProjectsDir(files: [:])
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let agg = JSONLParser().aggregateRollingWindow(
            endingAt: Date(),
            duration: 5 * 3600,
            rootDirectory: tempRoot
        )
        XCTAssertEqual(agg.totalTokens, 0)
        XCTAssertEqual(agg.recordCount, 0)
    }

    // MARK: - Helpers

    private func makeTempProjectsDir(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relPath, content) in files {
            let fileURL = root.appendingPathComponent(relPath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return root
    }
}
