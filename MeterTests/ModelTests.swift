import XCTest
@testable import Meter

final class ModelTests: XCTestCase {
    func test_usageWindow_percentRoundsToNearest() {
        XCTAssertEqual(UsageWindow(utilization: 0.6049, resetsAt: nil).percent, 60)
        XCTAssertEqual(UsageWindow(utilization: 0.605, resetsAt: nil).percent, 61)
        XCTAssertEqual(UsageWindow(utilization: 1.001, resetsAt: nil).percent, 100)
    }

    func test_usageWindow_warningAndDangerBands() {
        XCTAssertFalse(UsageWindow(utilization: 0.59, resetsAt: nil).isWarning)
        XCTAssertTrue(UsageWindow(utilization: 0.60, resetsAt: nil).isWarning)
        XCTAssertTrue(UsageWindow(utilization: 0.84, resetsAt: nil).isWarning)
        XCTAssertFalse(UsageWindow(utilization: 0.85, resetsAt: nil).isWarning)
        XCTAssertTrue(UsageWindow(utilization: 0.85, resetsAt: nil).isDanger)
        XCTAssertTrue(UsageWindow(utilization: 1.10, resetsAt: nil).isDanger)
    }

    func test_snapshot_headlineUtilizationPicksMaxAcrossWindows() {
        let s = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 0.32, resetsAt: nil),
            sevenDay: UsageWindow(utilization: 0.78, resetsAt: nil),
            source: .api,
            capturedAt: Date()
        )
        XCTAssertEqual(s.headlineUtilization, 0.78, accuracy: 0.0001)
    }

    func test_snapshot_headlineWithMissingFiveHour() {
        let s = UsageSnapshot(
            fiveHour: nil,
            sevenDay: UsageWindow(utilization: 0.4, resetsAt: nil),
            source: .api,
            capturedAt: Date()
        )
        XCTAssertEqual(s.headlineUtilization, 0.4, accuracy: 0.0001)
    }

    func test_snapshot_headlineWithBothMissing() {
        let s = UsageSnapshot(
            fiveHour: nil,
            sevenDay: nil,
            source: .estimated,
            capturedAt: Date(),
            estimatedFiveHourTokens: 100
        )
        XCTAssertEqual(s.headlineUtilization, 0)
    }

    func test_usageStateSnapshotHelper() {
        let s = UsageSnapshot(
            fiveHour: nil,
            sevenDay: nil,
            source: .api,
            capturedAt: Date()
        )
        XCTAssertEqual(UsageState.ok(s).snapshot, s)
        XCTAssertEqual(UsageState.estimated(s, underlyingMessage: "x").snapshot, s)
        XCTAssertNil(UsageState.loading.snapshot)
        XCTAssertNil(UsageState.missingToken.snapshot)
        XCTAssertNil(UsageState.error("nope").snapshot)
    }
}
