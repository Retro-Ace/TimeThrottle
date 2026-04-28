import Foundation

public struct AircraftSearchRegion: Equatable, Sendable {
    public var center: GuidanceCoordinate
    public var radiusMiles: Double

    public init(center: GuidanceCoordinate, radiusMiles: Double = 10) {
        self.center = center
        self.radiusMiles = Self.clampedRadiusMiles(radiusMiles)
    }

    public init(center: GuidanceCoordinate, latitudeDelta: Double = 0.5, longitudeDelta: Double = 0.5) {
        self.center = center
        let latitudeMiles = abs(latitudeDelta) * 69
        let longitudeMiles = abs(longitudeDelta) * max(cos(center.latitude * .pi / 180) * 69, 1)
        self.radiusMiles = Self.clampedRadiusMiles(max(latitudeMiles, longitudeMiles) / 2)
    }

    public var minimumLatitude: Double { center.latitude - latitudeDelta / 2 }
    public var maximumLatitude: Double { center.latitude + latitudeDelta / 2 }
    public var minimumLongitude: Double { center.longitude - longitudeDelta / 2 }
    public var maximumLongitude: Double { center.longitude + longitudeDelta / 2 }

    private var latitudeDelta: Double {
        (radiusMiles / 69) * 2
    }

    private var longitudeDelta: Double {
        let milesPerLongitudeDegree = max(cos(center.latitude * .pi / 180) * 69, 1)
        return (radiusMiles / milesPerLongitudeDegree) * 2
    }

    private static func clampedRadiusMiles(_ radiusMiles: Double) -> Double {
        min(max(radiusMiles, 5), 20)
    }
}

public struct NearbyLowAircraftConfiguration: Equatable, Sendable {
    public var radiusMiles: Double
    public var maximumAltitudeFeet: Double
    public var maximumPositionAgeSeconds: TimeInterval

    public init(
        radiusMiles: Double = 10,
        maximumAltitudeFeet: Double = 5_000,
        maximumPositionAgeSeconds: TimeInterval = 120
    ) {
        self.radiusMiles = min(max(radiusMiles, 5), 20)
        self.maximumAltitudeFeet = max(maximumAltitudeFeet, 0)
        self.maximumPositionAgeSeconds = max(maximumPositionAgeSeconds, 30)
    }

    public static let `default` = NearbyLowAircraftConfiguration()
}

public enum AircraftAltitudeSource: String, Codable, Sendable {
    case barometric
    case geometric
    case unavailable
}

public struct Aircraft: Identifiable, Equatable, Sendable {
    public var id: String
    public var callsign: String
    public var coordinate: GuidanceCoordinate
    public var altitudeMeters: Double?
    public var altitudeFeet: Double?
    public var altitudeSource: AircraftAltitudeSource
    public var headingDegrees: Double?
    public var groundSpeedKnots: Double?
    public var groundSpeedMPH: Double?
    public var distanceMeters: Double?
    public var distanceMiles: Double?
    public var lastPositionDate: Date?
    public var lastContactDate: Date?
    public var timePositionDate: Date?
    public var dataAgeSeconds: TimeInterval?
    public var isStale: Bool
    public var isLowNearbyAircraft: Bool

    public init(
        id: String,
        callsign: String,
        coordinate: GuidanceCoordinate,
        altitudeMeters: Double? = nil,
        altitudeFeet: Double? = nil,
        altitudeSource: AircraftAltitudeSource = .unavailable,
        headingDegrees: Double? = nil,
        groundSpeedKnots: Double? = nil,
        groundSpeedMPH: Double? = nil,
        distanceMeters: Double? = nil,
        distanceMiles: Double? = nil,
        lastPositionDate: Date? = nil,
        lastContactDate: Date? = nil,
        timePositionDate: Date? = nil,
        dataAgeSeconds: TimeInterval? = nil,
        isStale: Bool = false,
        isLowNearbyAircraft: Bool = false
    ) {
        self.id = id
        self.callsign = callsign
        self.coordinate = coordinate
        self.altitudeMeters = altitudeMeters
        self.altitudeFeet = altitudeFeet
        self.altitudeSource = altitudeSource
        self.headingDegrees = headingDegrees
        self.groundSpeedKnots = groundSpeedKnots
        self.groundSpeedMPH = groundSpeedMPH
        self.distanceMeters = distanceMeters
        self.distanceMiles = distanceMiles
        self.lastPositionDate = lastPositionDate
        self.lastContactDate = lastContactDate
        self.timePositionDate = timePositionDate
        self.dataAgeSeconds = dataAgeSeconds
        self.isStale = isStale
        self.isLowNearbyAircraft = isLowNearbyAircraft
    }
}

public protocol AircraftProvider: Sendable {
    func nearbyAircraft(in region: AircraftSearchRegion) async throws -> [Aircraft]
}

public struct AircraftLayerState: Equatable, Sendable {
    public var isVisible: Bool
    public var aircraft: [Aircraft]
    public var lastUpdated: Date?
    public var isStale: Bool

    public init(
        isVisible: Bool = false,
        aircraft: [Aircraft] = [],
        lastUpdated: Date? = nil,
        isStale: Bool = false
    ) {
        self.isVisible = isVisible
        self.aircraft = aircraft
        self.lastUpdated = lastUpdated
        self.isStale = isStale
    }
}

public enum AircraftPositionProjection {
    public static func projectedAircraft(
        from aircraft: [Aircraft],
        reference: GuidanceCoordinate? = nil,
        now: Date = Date(),
        staleTimeoutSeconds: TimeInterval = 90
    ) -> [Aircraft] {
        aircraft.compactMap { aircraft in
            projectedAircraft(
                aircraft,
                reference: reference,
                now: now,
                staleTimeoutSeconds: staleTimeoutSeconds
            )
        }
    }

    public static func projectedAircraft(
        _ aircraft: Aircraft,
        reference: GuidanceCoordinate? = nil,
        now: Date = Date(),
        staleTimeoutSeconds: TimeInterval = 90
    ) -> Aircraft? {
        let anchorDate = aircraft.timePositionDate ?? aircraft.lastPositionDate ?? aircraft.lastContactDate
        let elapsedSeconds = max(anchorDate.map { now.timeIntervalSince($0) } ?? aircraft.dataAgeSeconds ?? 0, 0)
        guard elapsedSeconds <= staleTimeoutSeconds else { return nil }

        var resolvedAircraft = aircraft
        if elapsedSeconds > 0,
           let headingDegrees = aircraft.headingDegrees,
           let speedMetersPerSecond = speedMetersPerSecond(for: aircraft),
           speedMetersPerSecond > 0 {
            resolvedAircraft.coordinate = projectedCoordinate(
                from: aircraft.coordinate,
                headingDegrees: headingDegrees,
                distanceMeters: speedMetersPerSecond * elapsedSeconds
            )
        }

        if let reference {
            let distanceMeters = reference.location.distance(from: resolvedAircraft.coordinate.location)
            resolvedAircraft.distanceMeters = distanceMeters
            resolvedAircraft.distanceMiles = distanceMeters / 1_609.344
        }
        resolvedAircraft.dataAgeSeconds = max(elapsedSeconds, aircraft.dataAgeSeconds ?? 0)
        resolvedAircraft.isStale = false
        return resolvedAircraft
    }

    private static func speedMetersPerSecond(for aircraft: Aircraft) -> Double? {
        if let groundSpeedMPH = aircraft.groundSpeedMPH {
            return groundSpeedMPH / 2.23693629
        }

        if let groundSpeedKnots = aircraft.groundSpeedKnots {
            return groundSpeedKnots / 1.94384449
        }

        return nil
    }

    private static func projectedCoordinate(
        from coordinate: GuidanceCoordinate,
        headingDegrees: Double,
        distanceMeters: Double
    ) -> GuidanceCoordinate {
        let earthRadiusMeters = 6_371_000.0
        let angularDistance = distanceMeters / earthRadiusMeters
        let bearing = headingDegrees * .pi / 180
        let startLatitude = coordinate.latitude * .pi / 180
        let startLongitude = coordinate.longitude * .pi / 180

        let projectedLatitude = asin(
            sin(startLatitude) * cos(angularDistance) +
                cos(startLatitude) * sin(angularDistance) * cos(bearing)
        )
        let projectedLongitude = startLongitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(startLatitude),
            cos(angularDistance) - sin(startLatitude) * sin(projectedLatitude)
        )
        let normalizedLongitude = (projectedLongitude * 180 / .pi + 540)
            .truncatingRemainder(dividingBy: 360) - 180

        return GuidanceCoordinate(
            latitude: projectedLatitude * 180 / .pi,
            longitude: normalizedLongitude
        )
    }
}
