import Foundation
#if canImport(OSLog)
import OSLog
#endif

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

    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.timethrottle.app", category: "EnforcementAlerts")
    #endif

    public init(
        endpoint: URL = OSMEnforcementAlertProvider.defaultEndpoint,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func enforcementAlerts(in region: EnforcementAlertSearchRegion) async throws -> [EnforcementAlert] {
        Self.logRequestStarted(region: region)

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
            Self.logHTTPStatus(httpResponse.statusCode)
            throw EnforcementAlertProviderError.httpStatus(httpResponse.statusCode)
        }

        let result = Self.parseAlertResult(from: data, reference: region.center)
        let filteredAlerts = result.alerts
            .filter { ($0.distanceMiles ?? .greatestFiniteMagnitude) <= region.radiusMiles }
        Self.logResult(
            region: region,
            rawCount: result.rawElementCount,
            validCoordinateCount: result.validCoordinateCount,
            decodedCount: result.alerts.count,
            returnedCount: filteredAlerts.count
        )
        return filteredAlerts
    }

    public static func parseAlerts(
        from data: Data,
        reference: GuidanceCoordinate,
        now: Date = Date()
    ) -> [EnforcementAlert] {
        parseAlertResult(from: data, reference: reference, now: now).alerts
    }

    private struct AlertParseResult {
        var alerts: [EnforcementAlert]
        var rawElementCount: Int
        var validCoordinateCount: Int
    }

    private static func parseAlertResult(
        from data: Data,
        reference: GuidanceCoordinate,
        now: Date = Date()
    ) -> AlertParseResult {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = object["elements"] as? [[String: Any]]
        else {
            return AlertParseResult(alerts: [], rawElementCount: 0, validCoordinateCount: 0)
        }

        var alertsByID: [String: EnforcementAlert] = [:]
        var validCoordinateCount = 0

        for element in elements {
            guard
                let elementIdentifier = element["id"],
                let coordinate = coordinate(from: element),
                isValidCoordinate(coordinate)
            else {
                continue
            }

            validCoordinateCount += 1

            guard
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

        let alerts = alertsByID.values.sorted {
            ($0.distanceMiles ?? .greatestFiniteMagnitude) < ($1.distanceMiles ?? .greatestFiniteMagnitude)
        }
        return AlertParseResult(
            alerts: alerts,
            rawElementCount: elements.count,
            validCoordinateCount: validCoordinateCount
        )
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
          node["camera:type"~"speed|red_light|redlight|traffic"](around:\(radiusMeters),\(latitude),\(longitude));
          node["device"="camera"]["enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
          node["man_made"="surveillance"]["surveillance"="traffic"](around:\(radiusMeters),\(latitude),\(longitude));
          node["man_made"="surveillance"]["surveillance:type"~"traffic|transport|road"](around:\(radiusMeters),\(latitude),\(longitude));
          node["surveillance:type"~"traffic|transport|road"](around:\(radiusMeters),\(latitude),\(longitude));
          way["highway"="speed_camera"](around:\(radiusMeters),\(latitude),\(longitude));
          way["enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
          way["camera:type"~"speed|red_light|redlight|traffic"](around:\(radiusMeters),\(latitude),\(longitude));
          way["device"="camera"]["enforcement"](around:\(radiusMeters),\(latitude),\(longitude));
          way["man_made"="surveillance"]["surveillance"="traffic"](around:\(radiusMeters),\(latitude),\(longitude));
          way["man_made"="surveillance"]["surveillance:type"~"traffic|transport|road"](around:\(radiusMeters),\(latitude),\(longitude));
          way["surveillance:type"~"traffic|transport|road"](around:\(radiusMeters),\(latitude),\(longitude));
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
        let cameraType = normalizedTagValue("camera:type", in: tags)

        if highway == "speed_camera" ||
            enforcement.contains("maxspeed") ||
            enforcement.contains("speed") ||
            cameraType.contains("speed") ||
            normalized.contains("speed_camera") ||
            normalized.contains("speed camera") {
            return .speedCamera
        }

        if normalizedTagValue("red_light_camera", in: tags).isAffirmativeOSMValue ||
            normalizedTagValue("traffic_signals:camera", in: tags).isAffirmativeOSMValue ||
            enforcement.contains("redlight") ||
            enforcement.contains("red_light") ||
            enforcement.contains("traffic_signals") ||
            cameraType.contains("redlight") ||
            cameraType.contains("red_light") ||
            normalized.contains("red_light_camera") ||
            normalized.contains("red light camera") {
            return .redLightCamera
        }

        if !enforcement.isEmpty ||
            !cameraType.isEmpty ||
            normalizedTagValue("type", in: tags) == "enforcement" ||
            isTrafficRelatedCameraOrSurveillance(tags) {
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

    private static func isTrafficRelatedCameraOrSurveillance(_ tags: [String: Any]) -> Bool {
        let device = normalizedTagValue("device", in: tags)
        let surveillance = normalizedTagValue("surveillance", in: tags)
        let surveillanceType = normalizedTagValue("surveillance:type", in: tags)
        let manMade = normalizedTagValue("man_made", in: tags)

        if device == "camera", !normalizedTagValue("enforcement", in: tags).isEmpty {
            return true
        }

        if manMade == "surveillance",
           surveillance.contains("traffic") || isTrafficSurveillanceType(surveillanceType) {
            return true
        }

        return isTrafficSurveillanceType(surveillanceType)
    }

    private static func isTrafficSurveillanceType(_ value: String) -> Bool {
        value.contains("traffic") || value.contains("transport") || value.contains("road")
    }

    private static func logRequestStarted(region: EnforcementAlertSearchRegion) {
        #if canImport(OSLog)
        logger.debug(
            "Enforcement provider request started center=\(roundedCoordinateText(region.center), privacy: .public) radiusMiles=\(region.radiusMiles, privacy: .public)"
        )
        #endif
    }

    private static func logHTTPStatus(_ statusCode: Int) {
        #if canImport(OSLog)
        logger.error("Enforcement provider HTTP status=\(statusCode, privacy: .public)")
        #endif
    }

    private static func logResult(
        region: EnforcementAlertSearchRegion,
        rawCount: Int,
        validCoordinateCount: Int,
        decodedCount: Int,
        returnedCount: Int
    ) {
        #if canImport(OSLog)
        logger.debug(
            "Enforcement provider result center=\(roundedCoordinateText(region.center), privacy: .public) radiusMiles=\(region.radiusMiles, privacy: .public) raw=\(rawCount, privacy: .public) validCoordinates=\(validCoordinateCount, privacy: .public) decoded=\(decodedCount, privacy: .public) returned=\(returnedCount, privacy: .public)"
        )
        #endif
    }

    private static func roundedCoordinateText(_ coordinate: GuidanceCoordinate) -> String {
        "\(String(format: "%.4f", coordinate.latitude)),\(String(format: "%.4f", coordinate.longitude))"
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
