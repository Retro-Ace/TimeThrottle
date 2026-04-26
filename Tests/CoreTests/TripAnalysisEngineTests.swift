import XCTest
@testable import TimeThrottleCore

final class TripAnalysisEngineTests: XCTestCase {
    func testTripAnalysisCountsTimeAboveAvailableSpeedLimitAndOverallResult() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [
            SpeedSample(timestamp: start, speedMilesPerHour: 80),
            SpeedSample(timestamp: start.addingTimeInterval(90 * 60), speedMilesPerHour: 80)
        ]

        let result = TripAnalysisEngine.analyze(
            input: TripAnalysisInput(
                baselineRouteETAMinutes: 120,
                distanceTraveledMiles: 120,
                currentSpeedHistory: samples,
                speedLimitMilesPerHour: 60
            )
        )

        XCTAssertEqual(result.actualTravelMinutes, 90, accuracy: 0.0001)
        XCTAssertEqual(result.averageTripSpeed, 80, accuracy: 0.0001)
        XCTAssertEqual(result.timeAboveSpeedLimit, 90, accuracy: 0.0001)
        XCTAssertEqual(result.timeLostBelowTargetPace, 0, accuracy: 0.0001)
        XCTAssertEqual(result.speedLimitMeasuredMinutes, 90, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, 30, accuracy: 0.0001)
        XCTAssertEqual(result.summary.netTimeGain, 30, accuracy: 0.0001)
    }

    func testTripAnalysisCountsSlowerIntervalsBelowAvailableSpeedLimit() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [
            SpeedSample(timestamp: start, speedMilesPerHour: 40),
            SpeedSample(timestamp: start.addingTimeInterval(150 * 60), speedMilesPerHour: 40)
        ]

        let result = TripAnalysisEngine.analyze(
            input: TripAnalysisInput(
                baselineRouteETAMinutes: 120,
                distanceTraveledMiles: 100,
                currentSpeedHistory: samples,
                speedLimitMilesPerHour: 50
            )
        )

        XCTAssertEqual(result.actualTravelMinutes, 150, accuracy: 0.0001)
        XCTAssertEqual(result.timeSavedBySpeeding, 0, accuracy: 0.0001)
        XCTAssertEqual(result.timeBelowSpeedLimit, 150, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, -30, accuracy: 0.0001)
        XCTAssertEqual(result.summary.timeLostBelowTargetPace, 150, accuracy: 0.0001)
    }

    func testTripAnalysisTreatsStoppedIntervalsAsBelowAvailableSpeedLimit() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [
            SpeedSample(timestamp: start, speedMilesPerHour: 0),
            SpeedSample(timestamp: start.addingTimeInterval(15 * 60), speedMilesPerHour: 0)
        ]

        let result = TripAnalysisEngine.analyze(
            input: TripAnalysisInput(
                baselineRouteETAMinutes: 10,
                distanceTraveledMiles: 1,
                currentSpeedHistory: samples,
                speedLimitMilesPerHour: 30
            )
        )

        XCTAssertEqual(result.timeSavedBySpeeding, 0, accuracy: 0.0001)
        XCTAssertEqual(result.timeLostBelowTargetPace, 15, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, -5, accuracy: 0.0001)
    }

    func testTripAnalysisAccumulatesIncrementallyWithoutStoringHistory() {
        var state = TripAnalysisState()
        state = TripAnalysisEngine.applying(
            update: TripAnalysisUpdate(
                deltaDistanceMiles: 40,
                deltaTimeMinutes: 30,
                speedMilesPerHour: 80,
                speedLimitMilesPerHour: 60
            ),
            to: state,
            speedLimitMilesPerHour: 60
        )
        state = TripAnalysisEngine.applying(
            update: TripAnalysisUpdate(
                deltaDistanceMiles: 10,
                deltaTimeMinutes: 15,
                speedMilesPerHour: 40,
                speedLimitMilesPerHour: 60
            ),
            to: state,
            speedLimitMilesPerHour: 60
        )

        let result = TripAnalysisEngine.summarize(
            state: state,
            baselineRouteETAMinutes: 50,
            baselineRouteDistanceMiles: 50
        )

        XCTAssertEqual(state.distanceTraveledMiles, 50, accuracy: 0.0001)
        XCTAssertEqual(state.timeAboveTargetSpeed, 30, accuracy: 0.0001)
        XCTAssertEqual(state.timeBelowTargetSpeed, 15, accuracy: 0.0001)
        XCTAssertEqual(result.timeSavedBySpeeding, 30, accuracy: 0.0001)
        XCTAssertEqual(result.timeLostBelowTargetPace, 15, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, 5, accuracy: 0.0001)
    }

    func testTripAnalysisSkipsSpeedLimitMetricsWhenLimitUnavailable() {
        var state = TripAnalysisState()
        state = TripAnalysisEngine.applying(
            update: TripAnalysisUpdate(
                deltaDistanceMiles: 10,
                deltaTimeMinutes: 10,
                speedMilesPerHour: 90
            ),
            to: state,
            speedLimitMilesPerHour: nil
        )
        state = TripAnalysisEngine.applying(
            update: TripAnalysisUpdate(
                deltaDistanceMiles: 5,
                deltaTimeMinutes: 5,
                speedMilesPerHour: 70,
                speedLimitMilesPerHour: 60
            ),
            to: state,
            speedLimitMilesPerHour: 60
        )

        XCTAssertEqual(state.timeAboveSpeedLimit, 5, accuracy: 0.0001)
        XCTAssertEqual(state.timeBelowSpeedLimit, 0, accuracy: 0.0001)
        XCTAssertEqual(state.speedLimitMeasuredMinutes, 5, accuracy: 0.0001)
        XCTAssertEqual(state.speedLimitUnavailableMinutes, 10, accuracy: 0.0001)
    }
}
