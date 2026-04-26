import Foundation

/// A single usage window reported by Anthropic (5-hour or 7-day).
///
/// `utilization` is normalized to the range `0.0 ... 1.0+`. Values above
/// `1.0` are possible if the user has exceeded the published limit.
public struct UsageWindow: Equatable, Sendable, Codable {
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public var percent: Int {
        Int((utilization * 100).rounded())
    }

    /// `true` once usage crosses the soft warning band (60 %).
    public var isWarning: Bool { utilization >= 0.60 && utilization < 0.85 }

    /// `true` once usage enters the danger band (85 %).
    public var isDanger: Bool { utilization >= 0.85 }
}
