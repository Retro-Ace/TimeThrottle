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
    public var targetSpeed: Double

    public init(
        baselineRouteETAMinutes: Double = 0,
        baselineRouteDistanceMiles: Double = 0,
        distanceTraveledMiles: Double = 0,
        currentSpeedHistory: [SpeedSample] = [],
        targetSpeed: Double = 0
    ) {
        self.baselineRouteETAMinutes = baselineRouteETAMinutes
        self.baselineRouteDistanceMiles = baselineRouteDistanceMiles
        self.distanceTraveledMiles = distanceTraveledMiles
        self.currentSpeedHistory = currentSpeedHistory
        self.targetSpeed = targetSpeed
    }
}

public struct TripAnalysisState: Equatable, Sendable {
    public var distanceTraveledMiles: Double
    public var actualTravelMinutes: Double
    public var timeAboveTargetSpeed: Double
    public var timeBelowTargetSpeed: Double
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double

    public init(
        distanceTraveledMiles: Double = 0,
        actualTravelMinutes: Double = 0,
        timeAboveTargetSpeed: Double = 0,
        timeBelowTargetSpeed: Double = 0,
        timeSavedBySpeeding: Double = 0,
        timeLostBelowTargetPace: Double = 0
    ) {
        self.distanceTraveledMiles = distanceTraveledMiles
        self.actualTravelMinutes = actualTravelMinutes
        self.timeAboveTargetSpeed = timeAboveTargetSpeed
        self.timeBelowTargetSpeed = timeBelowTargetSpeed
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
    }
}

public struct TripAnalysisUpdate: Equatable, Sendable {
    public var deltaDistanceMiles: Double
    public var deltaTimeMinutes: Double
    public var speedMilesPerHour: Double

    public init(
        deltaDistanceMiles: Double = 0,
        deltaTimeMinutes: Double = 0,
        speedMilesPerHour: Double = 0
    ) {
        self.deltaDistanceMiles = deltaDistanceMiles
        self.deltaTimeMinutes = deltaTimeMinutes
        self.speedMilesPerHour = speedMilesPerHour
    }
}

public struct TripSummary: Equatable, Sendable {
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double
    public var netTimeGain: Double

    public init(
        timeSavedBySpeeding: Double = 0,
        timeLostBelowTargetPace: Double = 0,
        netTimeGain: Double = 0
    ) {
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
        self.netTimeGain = netTimeGain
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
    public var summary: TripSummary

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
        self.summary = summary
    }
}

public enum TripAnalysisEngine {
    public static func applying(
        update: TripAnalysisUpdate,
        to state: TripAnalysisState,
        targetSpeed: Double
    ) -> TripAnalysisState {
        guard update.deltaTimeMinutes > 0 else { return state }

        var nextState = state
        nextState.distanceTraveledMiles += max(update.deltaDistanceMiles, 0)
        nextState.actualTravelMinutes += update.deltaTimeMinutes

        if targetSpeed > 0 {
            if update.speedMilesPerHour > targetSpeed {
                nextState.timeAboveTargetSpeed += update.deltaTimeMinutes
            } else if update.speedMilesPerHour < targetSpeed {
                nextState.timeBelowTargetSpeed += update.deltaTimeMinutes
            }

            let delta: Double
            if update.speedMilesPerHour <= 0 {
                delta = -update.deltaTimeMinutes
            } else {
                delta = PaceAnalysisMath.timeDeltaAgainstTargetPace(
                    targetSpeed: targetSpeed,
                    segment: DriveSegment(
                        speed: update.speedMilesPerHour,
                        minutes: update.deltaTimeMinutes
                    )
                )
            }

            if delta >= 0 {
                nextState.timeSavedBySpeeding += delta
            } else {
                nextState.timeLostBelowTargetPace += abs(delta)
            }
        }

        return nextState
    }

    public static func summarize(
        state: TripAnalysisState,
        baselineRouteETAMinutes: Double,
        baselineRouteDistanceMiles: Double = 0,
        targetSpeed: Double
    ) -> TripAnalysisResult {
        guard
            state.distanceTraveledMiles > 0,
            state.actualTravelMinutes > 0,
            targetSpeed > 0
        else {
            return TripAnalysisResult()
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
            netTimeGain: netTimeDifference
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
                    speedMilesPerHour: current.speedMilesPerHour
                ),
                to: state,
                targetSpeed: input.targetSpeed
            )
        }

        if input.distanceTraveledMiles > 0 {
            state.distanceTraveledMiles = input.distanceTraveledMiles
        }

        return summarize(
            state: state,
            baselineRouteETAMinutes: input.baselineRouteETAMinutes,
            baselineRouteDistanceMiles: input.baselineRouteDistanceMiles,
            targetSpeed: input.targetSpeed
        )
    }

    public static func state(
        from speedHistory: [SpeedSample],
        distanceTraveledMiles: Double = 0,
        targetSpeed: Double
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
                    speedMilesPerHour: current.speedMilesPerHour
                ),
                to: state,
                targetSpeed: targetSpeed
            )
        }

        if distanceTraveledMiles > 0 {
            state.distanceTraveledMiles = distanceTraveledMiles
        }

        return state
    }
}
