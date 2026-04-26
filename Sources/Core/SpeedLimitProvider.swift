import Foundation

public enum SpeedLimitEstimate: Equatable, Sendable {
    case estimate(SpeedLimitValue)
    case unavailable(reason: String)
}

public struct SpeedLimitValue: Equatable, Sendable {
    public var milesPerHour: Int
    public var confidence: Double
    public var roadName: String?
    public var wayId: Int64?
    public var source: String

    public init(
        milesPerHour: Int,
        confidence: Double = 0.7,
        roadName: String? = nil,
        wayId: Int64? = nil,
        source: String = "OpenStreetMap"
    ) {
        self.milesPerHour = milesPerHour
        self.confidence = min(max(confidence, 0), 1)
        self.roadName = roadName
        self.wayId = wayId
        self.source = source
    }

    public var currentSpeedLimitMPH: Int {
        milesPerHour
    }
}

public protocol SpeedLimitProvider: Sendable {
    func currentSpeedLimit(near coordinate: GuidanceCoordinate) async throws -> SpeedLimitEstimate
}

public struct OSMSpeedLimitResult: Equatable, Sendable {
    public var currentSpeedLimitMPH: Int
    public var confidence: Double
    public var source: String
    public var roadName: String?
    public var wayId: Int64?

    public init(
        currentSpeedLimitMPH: Int,
        confidence: Double,
        source: String = "OpenStreetMap",
        roadName: String? = nil,
        wayId: Int64? = nil
    ) {
        self.currentSpeedLimitMPH = currentSpeedLimitMPH
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
        self.roadName = roadName
        self.wayId = wayId
    }

    public var speedLimitValue: SpeedLimitValue {
        SpeedLimitValue(
            milesPerHour: currentSpeedLimitMPH,
            confidence: confidence,
            roadName: roadName,
            wayId: wayId,
            source: source
        )
    }
}

public struct OSMSpeedLimitCacheEntry: Codable, Equatable, Sendable {
    public var speedLimitMPH: Int
    public var confidence: Double
    public var roadName: String?
    public var wayId: Int64?
    public var source: String
    public var timestamp: Date

    public init(
        speedLimitMPH: Int,
        confidence: Double,
        roadName: String?,
        wayId: Int64?,
        source: String,
        timestamp: Date = Date()
    ) {
        self.speedLimitMPH = speedLimitMPH
        self.confidence = confidence
        self.roadName = roadName
        self.wayId = wayId
        self.source = source
        self.timestamp = timestamp
    }

    public var result: OSMSpeedLimitResult {
        OSMSpeedLimitResult(
            currentSpeedLimitMPH: speedLimitMPH,
            confidence: confidence,
            source: source,
            roadName: roadName,
            wayId: wayId
        )
    }
}

public enum OSMSpeedLimitCacheKey: Hashable, Sendable {
    case wayId(Int64)
    case coordinateCorridor(SpeedLimitSegmentCacheKey)
}

public struct SpeedLimitSegmentCacheKey: Hashable, Sendable {
    public var roundedLatitude: Int
    public var roundedLongitude: Int

    public init(coordinate: GuidanceCoordinate, precision: Double = 10_000) {
        self.roundedLatitude = Int((coordinate.latitude * precision).rounded())
        self.roundedLongitude = Int((coordinate.longitude * precision).rounded())
    }
}
