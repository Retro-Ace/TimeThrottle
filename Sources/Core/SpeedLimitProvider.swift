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
    public var roadClass: SpeedLimitRoadClass
    public var highwayTag: String?
    public var source: String

    public init(
        milesPerHour: Int,
        confidence: Double = 0.7,
        roadName: String? = nil,
        wayId: Int64? = nil,
        roadClass: SpeedLimitRoadClass = .unknown,
        highwayTag: String? = nil,
        source: String = "OpenStreetMap"
    ) {
        self.milesPerHour = milesPerHour
        self.confidence = min(max(confidence, 0), 1)
        self.roadName = roadName
        self.wayId = wayId
        self.roadClass = roadClass
        self.highwayTag = highwayTag
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
    public var roadClass: SpeedLimitRoadClass
    public var highwayTag: String?

    public init(
        currentSpeedLimitMPH: Int,
        confidence: Double,
        source: String = "OpenStreetMap",
        roadName: String? = nil,
        wayId: Int64? = nil,
        roadClass: SpeedLimitRoadClass = .unknown,
        highwayTag: String? = nil
    ) {
        self.currentSpeedLimitMPH = currentSpeedLimitMPH
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
        self.roadName = roadName
        self.wayId = wayId
        self.roadClass = roadClass
        self.highwayTag = highwayTag
    }

    public var speedLimitValue: SpeedLimitValue {
        SpeedLimitValue(
            milesPerHour: currentSpeedLimitMPH,
            confidence: confidence,
            roadName: roadName,
            wayId: wayId,
            roadClass: roadClass,
            highwayTag: highwayTag,
            source: source
        )
    }
}

public enum SpeedLimitRoadClass: String, Codable, Equatable, Sendable {
    case major
    case minor
    case unknown

    public init(highwayTag: String?) {
        let normalized = highwayTag?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "motorway", "motorway_link",
             "trunk", "trunk_link",
             "primary", "primary_link",
             "secondary", "secondary_link",
             "tertiary", "tertiary_link":
            self = .major
        case "residential", "living_street", "service", "unclassified",
             "track", "pedestrian", "footway", "cycleway", "path", "steps":
            self = .minor
        default:
            self = .unknown
        }
    }
}

public struct OSMSpeedLimitCacheEntry: Codable, Equatable, Sendable {
    public var speedLimitMPH: Int
    public var confidence: Double
    public var roadName: String?
    public var wayId: Int64?
    public var roadClass: SpeedLimitRoadClass
    public var highwayTag: String?
    public var source: String
    public var timestamp: Date

    public init(
        speedLimitMPH: Int,
        confidence: Double,
        roadName: String?,
        wayId: Int64?,
        roadClass: SpeedLimitRoadClass = .unknown,
        highwayTag: String? = nil,
        source: String,
        timestamp: Date = Date()
    ) {
        self.speedLimitMPH = speedLimitMPH
        self.confidence = confidence
        self.roadName = roadName
        self.wayId = wayId
        self.roadClass = roadClass
        self.highwayTag = highwayTag
        self.source = source
        self.timestamp = timestamp
    }

    public var result: OSMSpeedLimitResult {
        OSMSpeedLimitResult(
            currentSpeedLimitMPH: speedLimitMPH,
            confidence: confidence,
            source: source,
            roadName: roadName,
            wayId: wayId,
            roadClass: roadClass,
            highwayTag: highwayTag
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

public struct SpeedLimitHoldoverPolicy: Equatable, Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var speedLimitMPH: Int
        public var confidence: Double
        public var coordinate: GuidanceCoordinate
        public var timestamp: Date
        public var roadName: String?
        public var wayId: Int64?
        public var roadClass: SpeedLimitRoadClass
        public var highwayTag: String?
        public var source: String

        public init(
            speedLimitMPH: Int,
            confidence: Double = 0.7,
            coordinate: GuidanceCoordinate,
            timestamp: Date,
            roadName: String? = nil,
            wayId: Int64? = nil,
            roadClass: SpeedLimitRoadClass = .unknown,
            highwayTag: String? = nil,
            source: String = "OpenStreetMap"
        ) {
            self.speedLimitMPH = speedLimitMPH
            self.confidence = min(max(confidence, 0), 1)
            self.coordinate = coordinate
            self.timestamp = timestamp
            self.roadName = roadName
            self.wayId = wayId
            self.roadClass = roadClass
            self.highwayTag = highwayTag
            self.source = source
        }

        public init(result: OSMSpeedLimitResult, coordinate: GuidanceCoordinate, timestamp: Date) {
            self.init(
                speedLimitMPH: result.currentSpeedLimitMPH,
                confidence: result.confidence,
                coordinate: coordinate,
                timestamp: timestamp,
                roadName: result.roadName,
                wayId: result.wayId,
                roadClass: result.roadClass,
                highwayTag: result.highwayTag,
                source: result.source
            )
        }
    }

    public enum Resolution: Equatable, Sendable {
        case fresh(Snapshot)
        case holdover(Snapshot)
        case unavailable

        public var snapshot: Snapshot? {
            switch self {
            case .fresh(let snapshot), .holdover(let snapshot):
                return snapshot
            case .unavailable:
                return nil
            }
        }

        public var speedLimitMPH: Int? {
            snapshot?.speedLimitMPH
        }
    }

    public init() {}

    public static func resolve(
        freshResult: OSMSpeedLimitResult?,
        previousSnapshot: Snapshot?,
        coordinate: GuidanceCoordinate,
        now: Date = Date()
    ) -> Resolution {
        if let freshResult {
            return .fresh(Snapshot(result: freshResult, coordinate: coordinate, timestamp: now))
        }

        guard let previousSnapshot,
              isHoldoverValid(previousSnapshot, at: coordinate, now: now) else {
            return .unavailable
        }

        return .holdover(previousSnapshot)
    }

    public static func isHoldoverValid(
        _ snapshot: Snapshot,
        at coordinate: GuidanceCoordinate,
        now: Date = Date()
    ) -> Bool {
        let window = holdoverWindow(for: snapshot.roadClass)
        let elapsedSeconds = now.timeIntervalSince(snapshot.timestamp)
        let movedMiles = snapshot.coordinate.location.distance(from: coordinate.location) / 1_609.344

        return elapsedSeconds <= window.maximumAgeSeconds &&
            movedMiles <= window.maximumDistanceMiles
    }

    public static func holdoverWindow(
        for roadClass: SpeedLimitRoadClass
    ) -> (maximumDistanceMiles: Double, maximumAgeSeconds: TimeInterval) {
        switch roadClass {
        case .major:
            return (2.0, 5 * 60)
        case .minor:
            return (0.25, 90)
        case .unknown:
            return (0.75, 3 * 60)
        }
    }
}
