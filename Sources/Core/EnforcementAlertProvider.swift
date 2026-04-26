import Foundation

public enum EnforcementAlertType: String, Codable, CaseIterable, Sendable {
    case speedCamera
    case redLightCamera
    case policeReported
    case other

    public var title: String {
        switch self {
        case .speedCamera:
            return "Speed Camera"
        case .redLightCamera:
            return "Red-Light Camera"
        case .policeReported:
            return "Police Reported"
        case .other:
            return "Enforcement Report"
        }
    }
}

public struct EnforcementAlert: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var type: EnforcementAlertType
    public var coordinate: GuidanceCoordinate
    public var title: String
    public var distanceMiles: Double?
    public var bearingDegrees: Double?
    public var source: String
    public var confidence: Double?
    public var lastUpdated: Date?
    public var isStale: Bool

    public init(
        id: String,
        type: EnforcementAlertType,
        coordinate: GuidanceCoordinate,
        title: String? = nil,
        distanceMiles: Double? = nil,
        bearingDegrees: Double? = nil,
        source: String,
        confidence: Double? = nil,
        lastUpdated: Date? = nil,
        isStale: Bool = false
    ) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.title = title ?? type.title
        self.distanceMiles = distanceMiles
        self.bearingDegrees = bearingDegrees
        self.source = source
        self.confidence = confidence
        self.lastUpdated = lastUpdated
        self.isStale = isStale
    }
}

public struct EnforcementAlertSearchRegion: Equatable, Sendable {
    public var center: GuidanceCoordinate
    public var radiusMiles: Double

    public init(center: GuidanceCoordinate, radiusMiles: Double = 5) {
        self.center = center
        self.radiusMiles = min(max(radiusMiles, 1), 20)
    }
}

public protocol EnforcementAlertProvider: Sendable {
    func enforcementAlerts(in region: EnforcementAlertSearchRegion) async throws -> [EnforcementAlert]
}

public struct LocalEnforcementAlertProvider: EnforcementAlertProvider {
    private let alerts: [EnforcementAlert]

    public init(alerts: [EnforcementAlert] = []) {
        self.alerts = alerts
    }

    public func enforcementAlerts(in region: EnforcementAlertSearchRegion) async throws -> [EnforcementAlert] {
        alerts
            .compactMap { alert -> EnforcementAlert? in
                let distanceMiles = region.center.location.distance(from: alert.coordinate.location) / 1_609.344
                guard distanceMiles <= region.radiusMiles else { return nil }

                var resolvedAlert = alert
                resolvedAlert.distanceMiles = distanceMiles
                if let lastUpdated = resolvedAlert.lastUpdated {
                    resolvedAlert.isStale = Date().timeIntervalSince(lastUpdated) > 86_400
                }
                return resolvedAlert
            }
            .filter { !$0.isStale }
            .sorted { ($0.distanceMiles ?? .greatestFiniteMagnitude) < ($1.distanceMiles ?? .greatestFiniteMagnitude) }
    }
}

public actor EnforcementAlertService {
    private let provider: EnforcementAlertProvider

    public init(provider: EnforcementAlertProvider = LocalEnforcementAlertProvider()) {
        self.provider = provider
    }

    public func alerts(near coordinate: GuidanceCoordinate, radiusMiles: Double = 5) async throws -> [EnforcementAlert] {
        try await provider.enforcementAlerts(
            in: EnforcementAlertSearchRegion(center: coordinate, radiusMiles: radiusMiles)
        )
    }
}
