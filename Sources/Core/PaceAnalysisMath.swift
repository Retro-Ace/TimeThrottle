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

public enum PaceAnalysisMath {
    public static func timeDeltaAgainstTargetPace(
        targetSpeed: Double,
        segment: DriveSegment
    ) -> Double {
        guard targetSpeed > 0, segment.speed > 0, segment.minutes > 0 else { return 0 }

        let hoursDriven = segment.minutes / 60
        let distanceCovered = segment.speed * hoursDriven
        let targetPaceHours = distanceCovered / targetSpeed
        let targetPaceMinutes = targetPaceHours * 60

        return targetPaceMinutes - segment.minutes
    }
}
