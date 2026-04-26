import Foundation

/// One assistant turn worth of token usage parsed out of a Claude Code JSONL log.
public struct JSONLUsageRecord: Equatable, Sendable {
    public let timestamp: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int

    public init(
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int
    ) {
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }
}

public protocol JSONLAggregating: Sendable {
    /// Sums token usage across all `~/.claude/projects/<project>/*.jsonl` files
    /// that fall within `[now - duration, now]`. Returns the aggregate token
    /// count and the number of records contributing to it.
    func aggregateRollingWindow(
        endingAt now: Date,
        duration: TimeInterval,
        rootDirectory: URL
    ) -> (totalTokens: Int, recordCount: Int)
}

public struct JSONLParser: Sendable, JSONLAggregating {
    public init() {}

    /// Parses a single file. Malformed lines are silently skipped — Claude Code
    /// occasionally writes partial lines during crashes, and we want a best-
    /// effort estimate, not a hard failure.
    public func parse(fileAt url: URL) throws -> [JSONLUsageRecord] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        return parse(content: content)
    }

    public func parse(content: String) -> [JSONLUsageRecord] {
        var records: [JSONLUsageRecord] = []
        content.enumerateLines { line, _ in
            guard let lineData = line.data(using: .utf8) else { return }
            guard
                let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let record = Self.recordFrom(jsonObject: obj)
            else { return }
            records.append(record)
        }
        return records
    }

    static func recordFrom(jsonObject obj: [String: Any]) -> JSONLUsageRecord? {
        guard
            let timestampString = obj["timestamp"] as? String,
            let timestamp = parseTimestamp(timestampString),
            let message = obj["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

        if input + output + cacheCreate + cacheRead == 0 { return nil }

        return JSONLUsageRecord(
            timestamp: timestamp,
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: cacheCreate,
            cacheReadInputTokens: cacheRead
        )
    }

    static func parseTimestamp(_ s: String) -> Date? {
        let stripped = s.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: stripped)
    }

    public func aggregateRollingWindow(
        endingAt now: Date,
        duration: TimeInterval,
        rootDirectory: URL
    ) -> (totalTokens: Int, recordCount: Int) {
        let cutoff = now.addingTimeInterval(-duration)
        let files = jsonlFiles(under: rootDirectory)

        var total = 0
        var count = 0
        for file in files {
            guard let records = try? parse(fileAt: file) else { continue }
            for r in records where r.timestamp >= cutoff && r.timestamp <= now {
                total += r.totalTokens
                count += 1
            }
        }
        return (total, count)
    }

    public static func defaultProjectsDirectory() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func jsonlFiles(under directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            results.append(url)
        }
        return results
    }
}
