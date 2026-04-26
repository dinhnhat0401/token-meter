import Foundation

public enum UsageSource: String, Equatable, Sendable, Codable {
    /// Pulled directly from `api.anthropic.com/api/oauth/usage`.
    case api
    /// Estimated locally from `~/.claude/projects/*.jsonl` because the API was
    /// unreachable or returned a malformed response.
    case estimated
}

/// A point-in-time snapshot of usage for the current account.
public struct UsageSnapshot: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let source: UsageSource
    public let capturedAt: Date

    /// When `source == .estimated` and the API call failed, this is the raw
    /// token total observed across `~/.claude/projects/*.jsonl` for the rolling
    /// 5-hour window. Nil when we have a real API answer.
    public let estimatedFiveHourTokens: Int?

    public init(
        fiveHour: UsageWindow?,
        sevenDay: UsageWindow?,
        source: UsageSource,
        capturedAt: Date,
        estimatedFiveHourTokens: Int? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.source = source
        self.capturedAt = capturedAt
        self.estimatedFiveHourTokens = estimatedFiveHourTokens
    }

    /// The window most worth surfacing in the menu bar — whichever is closer
    /// to its limit. Falls back gracefully if one or both are absent.
    public var headlineUtilization: Double {
        let five = fiveHour?.utilization ?? 0
        let seven = sevenDay?.utilization ?? 0
        return max(five, seven)
    }
}
