import XCTest
@testable import TimeThrottleCore

final class TimeThrottleCoreTests: XCTestCase {
    func testTimeDeltaComparedToLimitReturnsSavedTimeWhenDrivingFasterThanTarget() {
        let delta = TimeThrottleCalculator.timeDeltaComparedToLimit(
            speedLimit: 60,
            segment: DriveSegment(speed: 80, minutes: 30)
        )

        XCTAssertEqual(delta, 10, accuracy: 0.0001)
    }

    func testTimeDeltaComparedToLimitReturnsLostTimeWhenDrivingSlowerThanTarget() {
        let delta = TimeThrottleCalculator.timeDeltaComparedToLimit(
            speedLimit: 60,
            segment: DriveSegment(speed: 40, minutes: 30)
        )

        XCTAssertEqual(delta, -10, accuracy: 0.0001)
    }

    func testTimeDeltaComparedToLimitReturnsZeroForInvalidInputs() {
        XCTAssertEqual(
            TimeThrottleCalculator.timeDeltaComparedToLimit(
                speedLimit: 0,
                segment: DriveSegment(speed: 80, minutes: 30)
            ),
            0
        )

        XCTAssertEqual(
            TimeThrottleCalculator.timeDeltaComparedToLimit(
                speedLimit: 60,
                segment: DriveSegment(speed: 0, minutes: 30)
            ),
            0
        )
    }
}
