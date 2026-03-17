import XCTest
@testable import TimeThrottleCore

final class SpeedCostCalculatorTests: XCTestCase {
    func testSpeedCostSummarySeparatesTimeSavedFuelPenaltyAndRisk() {
        let summary = SpeedCostCalculator.summarize(
            input: SpeedCostInput(
                distanceMiles: 120,
                speedLimit: 60,
                averageTripSpeed: 80,
                baselineTravelMinutes: 120,
                actualTravelMinutes: 90,
                ratedMPG: 30,
                observedMPG: 24,
                fuelPricePerGallon: 4
            )
        )

        XCTAssertEqual(summary.timeSavedMinutes, 30, accuracy: 0.0001)
        XCTAssertEqual(summary.trafficDelayMinutes, 0, accuracy: 0.0001)
        XCTAssertEqual(summary.baselineFuelUsedGallons, 4, accuracy: 0.0001)
        XCTAssertEqual(summary.actualFuelUsedGallons, 5, accuracy: 0.0001)
        XCTAssertEqual(summary.extraFuelUsedGallons, 1, accuracy: 0.0001)
        XCTAssertEqual(summary.fuelCostPenalty, 4, accuracy: 0.0001)
        XCTAssertEqual(summary.netBenefitMinutes, 30, accuracy: 0.0001)
        XCTAssertEqual(summary.ticketRisk, .high)
    }

    func testSpeedCostSummaryTracksTrafficDelayWhenTripIsSlower() {
        let summary = SpeedCostCalculator.summarize(
            input: SpeedCostInput(
                distanceMiles: 90,
                speedLimit: 60,
                averageTripSpeed: 50,
                baselineTravelMinutes: 90,
                actualTravelMinutes: 108,
                ratedMPG: 28,
                observedMPG: 23,
                fuelPricePerGallon: 3.50
            )
        )

        XCTAssertEqual(summary.timeSavedMinutes, 0, accuracy: 0.0001)
        XCTAssertEqual(summary.trafficDelayMinutes, 18, accuracy: 0.0001)
        XCTAssertEqual(summary.netBenefitMinutes, -18, accuracy: 0.0001)
        XCTAssertEqual(summary.ticketRisk, .low)
    }

    func testTicketRiskThresholdsMatchHeuristic() {
        XCTAssertEqual(SpeedCostCalculator.ticketRiskLevel(averageTripSpeed: 65, speedLimit: 60), .low)
        XCTAssertEqual(SpeedCostCalculator.ticketRiskLevel(averageTripSpeed: 75, speedLimit: 60), .moderate)
        XCTAssertEqual(SpeedCostCalculator.ticketRiskLevel(averageTripSpeed: 76, speedLimit: 60), .high)
    }

    func testInvalidInputsReturnEmptySummary() {
        XCTAssertEqual(
            SpeedCostCalculator.summarize(
                input: SpeedCostInput(
                    distanceMiles: 120,
                    speedLimit: 60,
                    averageTripSpeed: 80,
                    baselineTravelMinutes: 120,
                    actualTravelMinutes: 90,
                    ratedMPG: 0,
                    observedMPG: 24,
                    fuelPricePerGallon: 4
                )
            ),
            SpeedCostSummary()
        )
    }
}
