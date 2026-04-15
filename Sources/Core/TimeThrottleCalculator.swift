import Foundation

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

public enum TimeThrottleCalculator {
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
}
