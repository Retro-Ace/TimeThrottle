import XCTest
@testable import TimeThrottleCore

final class TripAnalysisEngineTests: XCTestCase {
    func testTripAnalysisSeparatesSpeedGainBelowTargetPaceLossAndFuelPenalty() {
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
                targetSpeed: 60,
                fuelModel: TripFuelModel(
                    ratedMPG: 30,
                    observedMPG: 24,
                    fuelPricePerGallon: 4
                )
            )
        )

        XCTAssertEqual(result.actualTravelMinutes, 90, accuracy: 0.0001)
        XCTAssertEqual(result.averageTripSpeed, 80, accuracy: 0.0001)
        XCTAssertEqual(result.timeSavedBySpeeding, 30, accuracy: 0.0001)
        XCTAssertEqual(result.timeLostBelowTargetPace, 0, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, 30, accuracy: 0.0001)
        XCTAssertEqual(result.fuelCostPenalty, 4, accuracy: 0.0001)
        XCTAssertEqual(result.summary.netTimeGain, 30, accuracy: 0.0001)
    }

    func testTripAnalysisCountsSlowerIntervalsAsTimeLostBelowTargetPace() {
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
                targetSpeed: 50
            )
        )

        XCTAssertEqual(result.actualTravelMinutes, 150, accuracy: 0.0001)
        XCTAssertEqual(result.timeSavedBySpeeding, 0, accuracy: 0.0001)
        XCTAssertEqual(result.timeLostBelowTargetPace, 30, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, -30, accuracy: 0.0001)
        XCTAssertEqual(result.summary.timeLostBelowTargetPace, 30, accuracy: 0.0001)
        XCTAssertEqual(result.summary.fuelPenalty, 0, accuracy: 0.0001)
    }

    func testTripAnalysisTreatsStoppedIntervalsAsTimeLostBelowTargetPace() {
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
                targetSpeed: 30
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
                speedMilesPerHour: 80
            ),
            to: state,
            targetSpeed: 60
        )
        state = TripAnalysisEngine.applying(
            update: TripAnalysisUpdate(
                deltaDistanceMiles: 10,
                deltaTimeMinutes: 15,
                speedMilesPerHour: 40
            ),
            to: state,
            targetSpeed: 60
        )

        let result = TripAnalysisEngine.summarize(
            state: state,
            baselineRouteETAMinutes: 50,
            baselineRouteDistanceMiles: 50,
            targetSpeed: 60
        )

        XCTAssertEqual(state.distanceTraveledMiles, 50, accuracy: 0.0001)
        XCTAssertEqual(state.timeAboveTargetSpeed, 30, accuracy: 0.0001)
        XCTAssertEqual(state.timeBelowTargetSpeed, 15, accuracy: 0.0001)
        XCTAssertEqual(result.timeSavedBySpeeding, 10, accuracy: 0.0001)
        XCTAssertEqual(result.timeLostBelowTargetPace, 5, accuracy: 0.0001)
        XCTAssertEqual(result.netTimeDifference, 5, accuracy: 0.0001)
    }
}
