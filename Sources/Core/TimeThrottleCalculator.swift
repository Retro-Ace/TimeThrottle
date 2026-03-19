import Foundation

public enum CalculationMode: String, CaseIterable, Identifiable, Sendable {
    case simple = "Simple"
    case speedAdjusted = "Speed-Adjusted"

    public var id: String { rawValue }

    public var footnote: String {
        switch self {
        case .simple:
            return "Counts time above the limit as time saved, and time below as time under target pace."
        case .speedAdjusted:
            return "Compares each segment to the time the same distance would take at the speed limit."
        }
    }
}

public struct DriveSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var speed: Double
    public var minutes: Double

    public init(id: UUID = UUID(), speed: Double, minutes: Double) {
        self.id = id
        self.speed = speed
        self.minutes = minutes
    }
}

public struct CalculationSummary: Equatable, Sendable {
    public var speedingMinutes: Double
    public var timeUnderTargetPaceMinutes: Double
    public var savedMinutes: Double
    public var lostMinutes: Double

    public init(
        speedingMinutes: Double = 0,
        timeUnderTargetPaceMinutes: Double = 0,
        savedMinutes: Double = 0,
        lostMinutes: Double = 0
    ) {
        self.speedingMinutes = speedingMinutes
        self.timeUnderTargetPaceMinutes = timeUnderTargetPaceMinutes
        self.savedMinutes = savedMinutes
        self.lostMinutes = lostMinutes
    }

    public var netMinutes: Double {
        savedMinutes - lostMinutes
    }
}

public enum TripComparisonInput: Equatable, Sendable {
    case averageSpeed(Double)
    case tripDurationMinutes(Double)
}

public struct TripComparisonSummary: Equatable, Sendable {
    public var distanceMiles: Double
    public var speedLimit: Double
    public var comparisonAverageSpeed: Double
    public var legalTravelMinutes: Double
    public var comparisonTravelMinutes: Double
    public var timeDeltaMinutes: Double
    public var isOverLimit: Bool

    public init(
        distanceMiles: Double = 0,
        speedLimit: Double = 0,
        comparisonAverageSpeed: Double = 0,
        legalTravelMinutes: Double = 0,
        comparisonTravelMinutes: Double = 0,
        timeDeltaMinutes: Double = 0,
        isOverLimit: Bool = false
    ) {
        self.distanceMiles = distanceMiles
        self.speedLimit = speedLimit
        self.comparisonAverageSpeed = comparisonAverageSpeed
        self.legalTravelMinutes = legalTravelMinutes
        self.comparisonTravelMinutes = comparisonTravelMinutes
        self.timeDeltaMinutes = timeDeltaMinutes
        self.isOverLimit = isOverLimit
    }
}

public enum TimeThrottleCalculator {
    public static func summarize(
        speedLimit: Double,
        segments: [DriveSegment],
        mode: CalculationMode
    ) -> CalculationSummary {
        guard speedLimit > 0 else { return CalculationSummary() }

        return segments.reduce(into: CalculationSummary()) { summary, segment in
            guard segment.speed > 0, segment.minutes > 0 else { return }

            if segment.speed > speedLimit {
                summary.speedingMinutes += segment.minutes
            } else if segment.speed < speedLimit {
                summary.timeUnderTargetPaceMinutes += segment.minutes
            }

            let delta: Double
            switch mode {
            case .simple:
                delta = segment.speed > speedLimit ? segment.minutes : (segment.speed < speedLimit ? -segment.minutes : 0)
            case .speedAdjusted:
                delta = timeDeltaComparedToLimit(speedLimit: speedLimit, segment: segment)
            }

            if delta >= 0 {
                summary.savedMinutes += delta
            } else {
                summary.lostMinutes += abs(delta)
            }
        }
    }

    public static func timeDeltaComparedToLimit(
        speedLimit: Double,
        segment: DriveSegment
    ) -> Double {
        guard speedLimit > 0, segment.speed > 0, segment.minutes > 0 else { return 0 }

        let hoursDriven = segment.minutes / 60
        let distanceCovered = segment.speed * hoursDriven
        let legalHours = distanceCovered / speedLimit
        let legalMinutes = legalHours * 60

        return legalMinutes - segment.minutes
    }

    public static func compareTrip(
        distanceMiles: Double,
        speedLimit: Double,
        input: TripComparisonInput
    ) -> TripComparisonSummary {
        guard distanceMiles > 0, speedLimit > 0 else { return TripComparisonSummary() }

        let comparisonAverageSpeed: Double
        let comparisonTravelMinutes: Double

        switch input {
        case .averageSpeed(let averageSpeed):
            guard averageSpeed > 0 else { return TripComparisonSummary() }
            comparisonAverageSpeed = averageSpeed
            comparisonTravelMinutes = (distanceMiles / averageSpeed) * 60
        case .tripDurationMinutes(let tripDurationMinutes):
            guard tripDurationMinutes > 0 else { return TripComparisonSummary() }
            comparisonTravelMinutes = tripDurationMinutes
            comparisonAverageSpeed = distanceMiles / (tripDurationMinutes / 60)
        }

        guard comparisonAverageSpeed > 0, comparisonTravelMinutes > 0 else {
            return TripComparisonSummary()
        }

        let legalTravelMinutes = (distanceMiles / speedLimit) * 60
        let timeDeltaMinutes = legalTravelMinutes - comparisonTravelMinutes

        return TripComparisonSummary(
            distanceMiles: distanceMiles,
            speedLimit: speedLimit,
            comparisonAverageSpeed: comparisonAverageSpeed,
            legalTravelMinutes: legalTravelMinutes,
            comparisonTravelMinutes: comparisonTravelMinutes,
            timeDeltaMinutes: timeDeltaMinutes,
            isOverLimit: comparisonAverageSpeed > speedLimit
        )
    }
}
