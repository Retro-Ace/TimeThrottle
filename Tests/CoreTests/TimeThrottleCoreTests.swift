import XCTest
@testable import TimeThrottleCore

final class TimeThrottleCoreTests: XCTestCase {
    func testTimeDeltaAgainstSpeedLimitReturnsPositiveDeltaWhenDrivingFasterThanLimit() {
        let delta = PaceAnalysisMath.timeDeltaAgainstSpeedLimit(
            speedLimit: 60,
            segment: DriveSegment(speed: 80, minutes: 30)
        )

        XCTAssertEqual(delta, 10, accuracy: 0.0001)
    }

    func testTimeDeltaAgainstSpeedLimitReturnsNegativeDeltaWhenDrivingSlowerThanLimit() {
        let delta = PaceAnalysisMath.timeDeltaAgainstSpeedLimit(
            speedLimit: 60,
            segment: DriveSegment(speed: 40, minutes: 30)
        )

        XCTAssertEqual(delta, -10, accuracy: 0.0001)
    }

    func testTimeDeltaAgainstSpeedLimitReturnsZeroForInvalidInputs() {
        XCTAssertEqual(
            PaceAnalysisMath.timeDeltaAgainstSpeedLimit(
                speedLimit: 0,
                segment: DriveSegment(speed: 80, minutes: 30)
            ),
            0
        )

        XCTAssertEqual(
            PaceAnalysisMath.timeDeltaAgainstSpeedLimit(
                speedLimit: 60,
                segment: DriveSegment(speed: 0, minutes: 30)
            ),
            0
        )
    }
}
