import XCTest
@testable import TimeThrottleCore

final class TimeThrottleCoreTests: XCTestCase {
    func testSimpleModeCountsMinutesAboveAndBelowLimit() {
        let summary = TimeThrottleCalculator.summarize(
            speedLimit: 70,
            segments: [
                DriveSegment(speed: 80, minutes: 20),
                DriveSegment(speed: 55, minutes: 15),
                DriveSegment(speed: 70, minutes: 10)
            ],
            mode: .simple
        )

        XCTAssertEqual(summary.speedingMinutes, 20)
        XCTAssertEqual(summary.trafficMinutes, 15)
        XCTAssertEqual(summary.savedMinutes, 20)
        XCTAssertEqual(summary.lostMinutes, 15)
        XCTAssertEqual(summary.netMinutes, 5)
    }

    func testSpeedAdjustedModeUsesDistanceAgainstLimit() {
        let summary = TimeThrottleCalculator.summarize(
            speedLimit: 70,
            segments: [
                DriveSegment(speed: 80, minutes: 30),
                DriveSegment(speed: 50, minutes: 30)
            ],
            mode: .speedAdjusted
        )

        XCTAssertEqual(summary.savedMinutes, 4.2857142857, accuracy: 0.0001)
        XCTAssertEqual(summary.lostMinutes, 8.5714285714, accuracy: 0.0001)
        XCTAssertEqual(summary.netMinutes, -4.2857142857, accuracy: 0.0001)
    }

    func testInvalidInputsCollapseToZero() {
        let summary = TimeThrottleCalculator.summarize(
            speedLimit: 0,
            segments: [
                DriveSegment(speed: -10, minutes: 15),
                DriveSegment(speed: 75, minutes: 0)
            ],
            mode: .speedAdjusted
        )

        XCTAssertEqual(summary, CalculationSummary())
    }

    func testTripComparisonWithAverageSpeedShowsTimeSaved() {
        let summary = TimeThrottleCalculator.compareTrip(
            distanceMiles: 120,
            speedLimit: 60,
            input: .averageSpeed(80)
        )

        XCTAssertEqual(summary.distanceMiles, 120)
        XCTAssertEqual(summary.speedLimit, 60)
        XCTAssertEqual(summary.comparisonAverageSpeed, 80, accuracy: 0.0001)
        XCTAssertEqual(summary.legalTravelMinutes, 120, accuracy: 0.0001)
        XCTAssertEqual(summary.comparisonTravelMinutes, 90, accuracy: 0.0001)
        XCTAssertEqual(summary.timeDeltaMinutes, 30, accuracy: 0.0001)
        XCTAssertTrue(summary.isOverLimit)
    }

    func testTripComparisonWithDurationMatchesAverageSpeedScenario() {
        let summary = TimeThrottleCalculator.compareTrip(
            distanceMiles: 120,
            speedLimit: 60,
            input: .tripDurationMinutes(90)
        )

        XCTAssertEqual(summary.comparisonAverageSpeed, 80, accuracy: 0.0001)
        XCTAssertEqual(summary.legalTravelMinutes, 120, accuracy: 0.0001)
        XCTAssertEqual(summary.comparisonTravelMinutes, 90, accuracy: 0.0001)
        XCTAssertEqual(summary.timeDeltaMinutes, 30, accuracy: 0.0001)
        XCTAssertTrue(summary.isOverLimit)
    }

    func testTripComparisonSlowerThanLimitShowsTimeLost() {
        let summary = TimeThrottleCalculator.compareTrip(
            distanceMiles: 100,
            speedLimit: 50,
            input: .averageSpeed(40)
        )

        XCTAssertEqual(summary.legalTravelMinutes, 120, accuracy: 0.0001)
        XCTAssertEqual(summary.comparisonTravelMinutes, 150, accuracy: 0.0001)
        XCTAssertEqual(summary.timeDeltaMinutes, -30, accuracy: 0.0001)
        XCTAssertFalse(summary.isOverLimit)
    }

    func testTripComparisonInvalidInputsReturnEmptySummary() {
        XCTAssertEqual(
            TimeThrottleCalculator.compareTrip(
                distanceMiles: 0,
                speedLimit: 60,
                input: .averageSpeed(80)
            ),
            TripComparisonSummary()
        )

        XCTAssertEqual(
            TimeThrottleCalculator.compareTrip(
                distanceMiles: 120,
                speedLimit: 60,
                input: .tripDurationMinutes(0)
            ),
            TripComparisonSummary()
        )
    }
}
