import XCTest
@testable import TimeThrottleCore

final class TimeThrottleCoreTests: XCTestCase {
    func testTimeDeltaAgainstTargetPaceReturnsSavedTimeWhenDrivingFasterThanTarget() {
        let delta = PaceAnalysisMath.timeDeltaAgainstTargetPace(
            targetSpeed: 60,
            segment: DriveSegment(speed: 80, minutes: 30)
        )

        XCTAssertEqual(delta, 10, accuracy: 0.0001)
    }

    func testTimeDeltaAgainstTargetPaceReturnsLostTimeWhenDrivingSlowerThanTarget() {
        let delta = PaceAnalysisMath.timeDeltaAgainstTargetPace(
            targetSpeed: 60,
            segment: DriveSegment(speed: 40, minutes: 30)
        )

        XCTAssertEqual(delta, -10, accuracy: 0.0001)
    }

    func testTimeDeltaAgainstTargetPaceReturnsZeroForInvalidInputs() {
        XCTAssertEqual(
            PaceAnalysisMath.timeDeltaAgainstTargetPace(
                targetSpeed: 0,
                segment: DriveSegment(speed: 80, minutes: 30)
            ),
            0
        )

        XCTAssertEqual(
            PaceAnalysisMath.timeDeltaAgainstTargetPace(
                targetSpeed: 60,
                segment: DriveSegment(speed: 0, minutes: 30)
            ),
            0
        )
    }
}
