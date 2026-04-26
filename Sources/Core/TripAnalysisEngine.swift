import Foundation

public struct SpeedSample: Equatable, Sendable {
    public var timestamp: Date
    public var speedMilesPerHour: Double

    public init(timestamp: Date, speedMilesPerHour: Double) {
        self.timestamp = timestamp
        self.speedMilesPerHour = speedMilesPerHour
    }
}

public struct TripAnalysisInput: Equatable, Sendable {
    public var baselineRouteETAMinutes: Double
    public var baselineRouteDistanceMiles: Double
    public var distanceTraveledMiles: Double
    public var currentSpeedHistory: [SpeedSample]
    public var speedLimitMilesPerHour: Double?

    public init(
        baselineRouteETAMinutes: Double = 0,
        baselineRouteDistanceMiles: Double = 0,
        distanceTraveledMiles: Double = 0,
        currentSpeedHistory: [SpeedSample] = [],
        speedLimitMilesPerHour: Double? = nil
    ) {
        self.baselineRouteETAMinutes = baselineRouteETAMinutes
        self.baselineRouteDistanceMiles = baselineRouteDistanceMiles
        self.distanceTraveledMiles = distanceTraveledMiles
        self.currentSpeedHistory = currentSpeedHistory
        self.speedLimitMilesPerHour = speedLimitMilesPerHour
    }
}

public struct TripAnalysisState: Equatable, Sendable {
    public var distanceTraveledMiles: Double
    public var actualTravelMinutes: Double
    public var timeAboveSpeedLimit: Double
    public var timeBelowSpeedLimit: Double
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double
    public var speedLimitMeasuredMinutes: Double
    public var speedLimitUnavailableMinutes: Double

    public var timeAboveTargetSpeed: Double {
        get { timeAboveSpeedLimit }
        set { timeAboveSpeedLimit = newValue }
    }

    public var timeBelowTargetSpeed: Double {
        get { timeBelowSpeedLimit }
        set { timeBelowSpeedLimit = newValue }
    }

    public init(
        distanceTraveledMiles: Double = 0,
        actualTravelMinutes: Double = 0,
        timeAboveTargetSpeed: Double = 0,
        timeBelowTargetSpeed: Double = 0,
        timeSavedBySpeeding: Double = 0,
        timeLostBelowTargetPace: Double = 0,
        speedLimitMeasuredMinutes: Double = 0,
        speedLimitUnavailableMinutes: Double = 0
    ) {
        self.distanceTraveledMiles = distanceTraveledMiles
        self.actualTravelMinutes = actualTravelMinutes
        self.timeAboveSpeedLimit = timeAboveTargetSpeed
        self.timeBelowSpeedLimit = timeBelowTargetSpeed
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
        self.speedLimitMeasuredMinutes = speedLimitMeasuredMinutes
        self.speedLimitUnavailableMinutes = speedLimitUnavailableMinutes
    }
}

public struct TripAnalysisUpdate: Equatable, Sendable {
    public var deltaDistanceMiles: Double
    public var deltaTimeMinutes: Double
    public var speedMilesPerHour: Double
    public var speedLimitMilesPerHour: Double?

    public init(
        deltaDistanceMiles: Double = 0,
        deltaTimeMinutes: Double = 0,
        speedMilesPerHour: Double = 0,
        speedLimitMilesPerHour: Double? = nil
    ) {
        self.deltaDistanceMiles = deltaDistanceMiles
        self.deltaTimeMinutes = deltaTimeMinutes
        self.speedMilesPerHour = speedMilesPerHour
        self.speedLimitMilesPerHour = speedLimitMilesPerHour
    }
}

public struct TripSummary: Equatable, Sendable {
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double
    public var netTimeGain: Double
    public var speedLimitMeasuredMinutes: Double
    public var speedLimitUnavailableMinutes: Double

    public var speedLimitCoverageRatio: Double? {
        let total = speedLimitMeasuredMinutes + speedLimitUnavailableMinutes
        guard total > 0 else { return nil }
        return speedLimitMeasuredMinutes / total
    }

    public init(
        timeSavedBySpeeding: Double = 0,
        timeLostBelowTargetPace: Double = 0,
        netTimeGain: Double = 0,
        speedLimitMeasuredMinutes: Double = 0,
        speedLimitUnavailableMinutes: Double = 0
    ) {
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
        self.netTimeGain = netTimeGain
        self.speedLimitMeasuredMinutes = speedLimitMeasuredMinutes
        self.speedLimitUnavailableMinutes = speedLimitUnavailableMinutes
    }
}

public struct TripAnalysisResult: Equatable, Sendable {
    public var baselineRouteETAMinutes: Double
    public var baselineRouteDistanceMiles: Double
    public var actualTravelMinutes: Double
    public var projectedTravelMinutes: Double
    public var remainingTravelMinutes: Double
    public var averageTripSpeed: Double
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double
    public var netTimeDifference: Double
    public var speedLimitMeasuredMinutes: Double
    public var speedLimitUnavailableMinutes: Double
    public var summary: TripSummary

    public var timeAboveSpeedLimit: Double {
        timeSavedBySpeeding
    }

    public var timeBelowSpeedLimit: Double {
        timeLostBelowTargetPace
    }

    public var speedLimitCoverageRatio: Double? {
        let total = speedLimitMeasuredMinutes + speedLimitUnavailableMinutes
        guard total > 0 else { return nil }
        return speedLimitMeasuredMinutes / total
    }

    public init(
        baselineRouteETAMinutes: Double = 0,
        baselineRouteDistanceMiles: Double = 0,
        actualTravelMinutes: Double = 0,
        projectedTravelMinutes: Double = 0,
        remainingTravelMinutes: Double = 0,
        averageTripSpeed: Double = 0,
        timeSavedBySpeeding: Double = 0,
        timeLostBelowTargetPace: Double = 0,
        netTimeDifference: Double = 0,
        speedLimitMeasuredMinutes: Double = 0,
        speedLimitUnavailableMinutes: Double = 0,
        summary: TripSummary = TripSummary()
    ) {
        self.baselineRouteETAMinutes = baselineRouteETAMinutes
        self.baselineRouteDistanceMiles = baselineRouteDistanceMiles
        self.actualTravelMinutes = actualTravelMinutes
        self.projectedTravelMinutes = projectedTravelMinutes
        self.remainingTravelMinutes = remainingTravelMinutes
        self.averageTripSpeed = averageTripSpeed
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
        self.netTimeDifference = netTimeDifference
        self.speedLimitMeasuredMinutes = speedLimitMeasuredMinutes
        self.speedLimitUnavailableMinutes = speedLimitUnavailableMinutes
        self.summary = summary
    }
}

public enum TripAnalysisEngine {
    public static let defaultSpeedLimitToleranceMPH: Double = 2

    public static func applying(
        update: TripAnalysisUpdate,
        to state: TripAnalysisState,
        speedLimitMilesPerHour: Double?,
        toleranceMPH: Double = defaultSpeedLimitToleranceMPH
    ) -> TripAnalysisState {
        guard update.deltaTimeMinutes > 0 else { return state }

        var nextState = state
        nextState.distanceTraveledMiles += max(update.deltaDistanceMiles, 0)
        nextState.actualTravelMinutes += update.deltaTimeMinutes

        guard let speedLimitMilesPerHour, speedLimitMilesPerHour > 0 else {
            nextState.speedLimitUnavailableMinutes += update.deltaTimeMinutes
            return nextState
        }

        nextState.speedLimitMeasuredMinutes += update.deltaTimeMinutes

        if update.speedMilesPerHour > speedLimitMilesPerHour + toleranceMPH {
            nextState.timeAboveSpeedLimit += update.deltaTimeMinutes
        } else if update.speedMilesPerHour < speedLimitMilesPerHour - toleranceMPH {
            nextState.timeBelowSpeedLimit += update.deltaTimeMinutes
        }

        nextState.timeSavedBySpeeding = nextState.timeAboveSpeedLimit
        nextState.timeLostBelowTargetPace = nextState.timeBelowSpeedLimit
        return nextState
    }

    public static func summarize(
        state: TripAnalysisState,
        baselineRouteETAMinutes: Double,
        baselineRouteDistanceMiles: Double = 0
    ) -> TripAnalysisResult {
        guard
            state.distanceTraveledMiles > 0,
            state.actualTravelMinutes > 0
        else {
            return TripAnalysisResult(
                speedLimitMeasuredMinutes: state.speedLimitMeasuredMinutes,
                speedLimitUnavailableMinutes: state.speedLimitUnavailableMinutes
            )
        }

        let resolvedBaselineDistanceMiles = max(baselineRouteDistanceMiles, state.distanceTraveledMiles)
        let averageTripSpeed = state.distanceTraveledMiles / (state.actualTravelMinutes / 60)

        let projectedTravelMinutes: Double
        if resolvedBaselineDistanceMiles > 0 {
            projectedTravelMinutes = (state.actualTravelMinutes / state.distanceTraveledMiles) * resolvedBaselineDistanceMiles
        } else {
            projectedTravelMinutes = state.actualTravelMinutes
        }

        let remainingTravelMinutes = max(projectedTravelMinutes - state.actualTravelMinutes, 0)
        let netTimeDifference: Double
        if baselineRouteETAMinutes > 0 {
            netTimeDifference = baselineRouteETAMinutes - projectedTravelMinutes
        } else {
            netTimeDifference = state.timeSavedBySpeeding - state.timeLostBelowTargetPace
        }

        let summary = TripSummary(
            timeSavedBySpeeding: state.timeSavedBySpeeding,
            timeLostBelowTargetPace: state.timeLostBelowTargetPace,
            netTimeGain: netTimeDifference,
            speedLimitMeasuredMinutes: state.speedLimitMeasuredMinutes,
            speedLimitUnavailableMinutes: state.speedLimitUnavailableMinutes
        )

        return TripAnalysisResult(
            baselineRouteETAMinutes: baselineRouteETAMinutes,
            baselineRouteDistanceMiles: resolvedBaselineDistanceMiles,
            actualTravelMinutes: state.actualTravelMinutes,
            projectedTravelMinutes: projectedTravelMinutes,
            remainingTravelMinutes: remainingTravelMinutes,
            averageTripSpeed: averageTripSpeed,
            timeSavedBySpeeding: state.timeSavedBySpeeding,
            timeLostBelowTargetPace: state.timeLostBelowTargetPace,
            netTimeDifference: netTimeDifference,
            speedLimitMeasuredMinutes: state.speedLimitMeasuredMinutes,
            speedLimitUnavailableMinutes: state.speedLimitUnavailableMinutes,
            summary: summary
        )
    }

    public static func analyze(input: TripAnalysisInput) -> TripAnalysisResult {
        var state = TripAnalysisState()

        for (current, next) in zip(input.currentSpeedHistory, input.currentSpeedHistory.dropFirst()) {
            let deltaTimeMinutes = next.timestamp.timeIntervalSince(current.timestamp) / 60
            guard deltaTimeMinutes > 0 else { continue }

            let deltaDistanceMiles = max(current.speedMilesPerHour, 0) * (deltaTimeMinutes / 60)
            state = applying(
                update: TripAnalysisUpdate(
                    deltaDistanceMiles: deltaDistanceMiles,
                    deltaTimeMinutes: deltaTimeMinutes,
                    speedMilesPerHour: current.speedMilesPerHour,
                    speedLimitMilesPerHour: input.speedLimitMilesPerHour
                ),
                to: state,
                speedLimitMilesPerHour: input.speedLimitMilesPerHour
            )
        }

        if input.distanceTraveledMiles > 0 {
            state.distanceTraveledMiles = input.distanceTraveledMiles
        }

        return summarize(
            state: state,
            baselineRouteETAMinutes: input.baselineRouteETAMinutes,
            baselineRouteDistanceMiles: input.baselineRouteDistanceMiles
        )
    }

    public static func state(
        from speedHistory: [SpeedSample],
        distanceTraveledMiles: Double = 0,
        speedLimitMilesPerHour: Double?
    ) -> TripAnalysisState {
        var state = TripAnalysisState()

        for (current, next) in zip(speedHistory, speedHistory.dropFirst()) {
            let deltaTimeMinutes = next.timestamp.timeIntervalSince(current.timestamp) / 60
            guard deltaTimeMinutes > 0 else { continue }

            let deltaDistanceMiles = max(current.speedMilesPerHour, 0) * (deltaTimeMinutes / 60)
            state = applying(
                update: TripAnalysisUpdate(
                    deltaDistanceMiles: deltaDistanceMiles,
                    deltaTimeMinutes: deltaTimeMinutes,
                    speedMilesPerHour: current.speedMilesPerHour,
                    speedLimitMilesPerHour: speedLimitMilesPerHour
                ),
                to: state,
                speedLimitMilesPerHour: speedLimitMilesPerHour
            )
        }

        if distanceTraveledMiles > 0 {
            state.distanceTraveledMiles = distanceTraveledMiles
        }

        return state
    }
}
