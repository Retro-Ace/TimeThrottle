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
            return "Reported Enforcement"
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

public enum EnforcementAlertProviderError: Error, Equatable, Sendable {
    case invalidEndpoint
    case httpStatus(Int)
    case invalidResponse
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

public actor OSMEnforcementAlertProvider: EnforcementAlertProvider {
    public static let defaultEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    private let endpoint: URL
    private let session: URLSession

    public init(
        endpoint: URL = OSMEnforcementAlertProvider.defaultEndpoint,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func enforcementAlerts(in region: EnforcementAlertSearchRegion) async throws -> [EnforcementAlert] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 14
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("TimeThrottle/2.0 passive-enforcement-alerts", forHTTPHeaderField: "User-Agent")

        let query = Self.overpassQuery(for: region)
        guard let encodedQuery = Self.formEncoded(query) else {
            throw EnforcementAlertProviderError.invalidEndpoint
        }
        request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw EnforcementAlertProviderError.httpStatus(httpResponse.statusCode)
        }

        return Self.parseAlerts(from: data, reference: region.center)
            .filter { ($0.distanceMiles ?? .greatestFiniteMagnitude) <= region.radiusMiles }
    }

    public static func parseAlerts(
        from data: Data,
        reference: GuidanceCoordinate,
        now: Date = Date()
    ) -> [EnforcementAlert] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = object["elements"] as? [[String: Any]]
        else {
            return []
        }

        var alertsByID: [String: EnforcementAlert] = [:]

        for element in elements {
            guard
                let elementIdentifier = element["id"],
                let coordinate = coordinate(from: element),
                isValidCoordinate(coordinate),
                let tags = element["tags"] as? [String: Any],
                let alertType = alertType(from: tags)
            else {
                continue
            }

            let typeName = (element["type"] as? String) ?? "element"
            let id = "osm-\(typeName)-\(elementIdentifier)"
            let distanceMiles = reference.location.distance(from: coordinate.location) / 1_609.344
            let alert = EnforcementAlert(
                id: id,
                type: alertType,
                coordinate: coordinate,
                title: title(for: alertType, tags: tags),
                distanceMiles: distanceMiles,
                bearingDegrees: bearingDegrees(from: reference, to: coordinate),
                source: "OpenStreetMap Overpass",
                confidence: confidence(for: alertType, tags: tags),
                lastUpdated: nil,
                isStale: false
            )
            alertsByID[id] = alert
        }

        return alertsByID.values.sorted {
            ($0.distanceMiles ?? .greatestFiniteMagnitude) < ($1.distanceMiles ?? .greatestFiniteMagnitude)
        }
    }

    private static func overpassQuery(for region: EnforcementAlertSearchRegion) -> String {
        let radiusMeters = Int((region.radiusMiles * 1_609.344).rounded())
        let latitude = region.center.latitude
        let longitude = region.center.longitude

        return """
        [out:json][timeout:12];
        (
          node["highway"="speed_camera"](around:\(radiusMeters),\(latitude),\(longitude));
          node["enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
          node["red_light_camera"](around:\(radiusMeters),\(latitude),\(longitude));
          node["traffic_signals:camera"](around:\(radiusMeters),\(latitude),\(longitude));
          way["highway"="speed_camera"](around:\(radiusMeters),\(latitude),\(longitude));
          way["enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
          relation["type"="enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
          relation["enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
        );
        out center tags;
        """
    }

    private static func formEncoded(_ text: String) -> String? {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "+&=")
        return text.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }

    private static func coordinate(from element: [String: Any]) -> GuidanceCoordinate? {
        if let latitude = element["lat"] as? Double,
           let longitude = element["lon"] as? Double {
            return GuidanceCoordinate(latitude: latitude, longitude: longitude)
        }

        guard let center = element["center"] as? [String: Any],
              let latitude = center["lat"] as? Double,
              let longitude = center["lon"] as? Double else {
            return nil
        }

        return GuidanceCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func isValidCoordinate(_ coordinate: GuidanceCoordinate) -> Bool {
        coordinate.latitude >= -90 &&
            coordinate.latitude <= 90 &&
            coordinate.longitude >= -180 &&
            coordinate.longitude <= 180
    }

    private static func alertType(from tags: [String: Any]) -> EnforcementAlertType? {
        let normalized = normalizedTagText(tags)
        let highway = normalizedTagValue("highway", in: tags)
        let enforcement = normalizedTagValue("enforcement", in: tags)

        if highway == "speed_camera" ||
            enforcement.contains("maxspeed") ||
            enforcement.contains("speed") ||
            normalized.contains("speed_camera") ||
            normalized.contains("speed camera") {
            return .speedCamera
        }

        if normalizedTagValue("red_light_camera", in: tags).isAffirmativeOSMValue ||
            normalizedTagValue("traffic_signals:camera", in: tags).isAffirmativeOSMValue ||
            enforcement.contains("redlight") ||
            enforcement.contains("red_light") ||
            enforcement.contains("traffic_signals") ||
            normalized.contains("red_light_camera") ||
            normalized.contains("red light camera") {
            return .redLightCamera
        }

        if !enforcement.isEmpty || normalizedTagValue("type", in: tags) == "enforcement" {
            return .other
        }

        return nil
    }

    private static func title(for type: EnforcementAlertType, tags: [String: Any]) -> String {
        if let name = tags["name"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        return type.title
    }

    private static func confidence(for type: EnforcementAlertType, tags: [String: Any]) -> Double {
        switch type {
        case .speedCamera, .redLightCamera:
            return 0.78
        case .policeReported, .other:
            return tags.isEmpty ? 0.55 : 0.68
        }
    }

    private static func normalizedTagValue(_ key: String, in tags: [String: Any]) -> String {
        guard let value = tags[key] else { return "" }
        return "\(value)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedTagText(_ tags: [String: Any]) -> String {
        tags
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
            .lowercased()
    }

    private static func bearingDegrees(
        from start: GuidanceCoordinate,
        to end: GuidanceCoordinate
    ) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) -
            sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

public actor EnforcementAlertService {
    private let provider: EnforcementAlertProvider

    public init(provider: EnforcementAlertProvider = OSMEnforcementAlertProvider()) {
        self.provider = provider
    }

    public func alerts(near coordinate: GuidanceCoordinate, radiusMiles: Double = 5) async throws -> [EnforcementAlert] {
        try await provider.enforcementAlerts(
            in: EnforcementAlertSearchRegion(center: coordinate, radiusMiles: radiusMiles)
        )
    }
}

private extension String {
    var isAffirmativeOSMValue: Bool {
        switch self {
        case "yes", "true", "1", "camera", "red_light", "red light", "red_light_camera", "traffic_signals":
            return true
        default:
            return false
        }
    }
}
