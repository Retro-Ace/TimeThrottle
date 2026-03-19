import Foundation

public struct SpeedCostInput: Equatable, Sendable {
    public var distanceMiles: Double
    public var speedLimit: Double
    public var averageTripSpeed: Double
    public var baselineTravelMinutes: Double
    public var actualTravelMinutes: Double
    public var ratedMPG: Double
    public var observedMPG: Double
    public var fuelPricePerGallon: Double

    public init(
        distanceMiles: Double = 0,
        speedLimit: Double = 0,
        averageTripSpeed: Double = 0,
        baselineTravelMinutes: Double = 0,
        actualTravelMinutes: Double = 0,
        ratedMPG: Double = 0,
        observedMPG: Double = 0,
        fuelPricePerGallon: Double = 0
    ) {
        self.distanceMiles = distanceMiles
        self.speedLimit = speedLimit
        self.averageTripSpeed = averageTripSpeed
        self.baselineTravelMinutes = baselineTravelMinutes
        self.actualTravelMinutes = actualTravelMinutes
        self.ratedMPG = ratedMPG
        self.observedMPG = observedMPG
        self.fuelPricePerGallon = fuelPricePerGallon
    }
}

public enum TicketRiskLevel: String, Equatable, Sendable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

public struct SpeedCostSummary: Equatable, Sendable {
    public var timeSavedMinutes: Double
    public var timeUnderTargetPaceMinutes: Double
    public var baselineFuelUsedGallons: Double
    public var actualFuelUsedGallons: Double
    public var extraFuelUsedGallons: Double
    public var fuelCostPenalty: Double
    public var ticketRisk: TicketRiskLevel

    public init(
        timeSavedMinutes: Double = 0,
        timeUnderTargetPaceMinutes: Double = 0,
        baselineFuelUsedGallons: Double = 0,
        actualFuelUsedGallons: Double = 0,
        extraFuelUsedGallons: Double = 0,
        fuelCostPenalty: Double = 0,
        ticketRisk: TicketRiskLevel = .low
    ) {
        self.timeSavedMinutes = timeSavedMinutes
        self.timeUnderTargetPaceMinutes = timeUnderTargetPaceMinutes
        self.baselineFuelUsedGallons = baselineFuelUsedGallons
        self.actualFuelUsedGallons = actualFuelUsedGallons
        self.extraFuelUsedGallons = extraFuelUsedGallons
        self.fuelCostPenalty = fuelCostPenalty
        self.ticketRisk = ticketRisk
    }

    public var netBenefitMinutes: Double {
        timeSavedMinutes - timeUnderTargetPaceMinutes
    }
}

public enum SpeedCostCalculator {
    public static func summarize(input: SpeedCostInput) -> SpeedCostSummary {
        guard
            input.distanceMiles > 0,
            input.speedLimit > 0,
            input.averageTripSpeed > 0,
            input.baselineTravelMinutes > 0,
            input.actualTravelMinutes > 0,
            input.ratedMPG > 0,
            input.observedMPG > 0,
            input.fuelPricePerGallon >= 0
        else {
            return SpeedCostSummary()
        }

        let timeDeltaMinutes = input.baselineTravelMinutes - input.actualTravelMinutes
        let timeSavedMinutes = max(timeDeltaMinutes, 0)
        let timeUnderTargetPaceMinutes = max(-timeDeltaMinutes, 0)

        let baselineFuelUsedGallons = input.distanceMiles / input.ratedMPG
        let actualFuelUsedGallons = input.distanceMiles / input.observedMPG
        let extraFuelUsedGallons = max(actualFuelUsedGallons - baselineFuelUsedGallons, 0)
        let fuelCostPenalty = extraFuelUsedGallons * input.fuelPricePerGallon

        return SpeedCostSummary(
            timeSavedMinutes: timeSavedMinutes,
            timeUnderTargetPaceMinutes: timeUnderTargetPaceMinutes,
            baselineFuelUsedGallons: baselineFuelUsedGallons,
            actualFuelUsedGallons: actualFuelUsedGallons,
            extraFuelUsedGallons: extraFuelUsedGallons,
            fuelCostPenalty: fuelCostPenalty,
            ticketRisk: ticketRiskLevel(
                averageTripSpeed: input.averageTripSpeed,
                speedLimit: input.speedLimit
            )
        )
    }

    public static func ticketRiskLevel(
        averageTripSpeed: Double,
        speedLimit: Double
    ) -> TicketRiskLevel {
        guard averageTripSpeed > 0, speedLimit > 0 else { return .low }

        if averageTripSpeed <= speedLimit + 5 {
            return .low
        }

        if averageTripSpeed <= speedLimit + 15 {
            return .moderate
        }

        return .high
    }
}
