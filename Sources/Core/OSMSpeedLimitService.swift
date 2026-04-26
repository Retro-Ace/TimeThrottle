import Foundation

public actor OSMSpeedLimitService: SpeedLimitProvider {
    private let endpoint: URL
    private let session: URLSession
    private let minimumConfidence: Double
    private let wayCacheTTL: TimeInterval
    private let coordinateCacheTTL: TimeInterval
    private var cache: [OSMSpeedLimitCacheKey: OSMSpeedLimitCacheEntry] = [:]

    public init(
        endpoint: URL = URL(string: "https://overpass-api.de/api/interpreter")!,
        session: URLSession = .shared,
        minimumConfidence: Double = 0.55,
        wayCacheTTL: TimeInterval = 7 * 24 * 60 * 60,
        coordinateCacheTTL: TimeInterval = 6 * 60 * 60
    ) {
        self.endpoint = endpoint
        self.session = session
        self.minimumConfidence = minimumConfidence
        self.wayCacheTTL = wayCacheTTL
        self.coordinateCacheTTL = coordinateCacheTTL
    }

    public func currentSpeedLimit(near coordinate: GuidanceCoordinate) async throws -> SpeedLimitEstimate {
        switch try await currentSpeedLimitResult(near: coordinate) {
        case .some(let result):
            return .estimate(result.speedLimitValue)
        case .none:
            return .unavailable(reason: "No confident OpenStreetMap speed-limit estimate near current road.")
        }
    }

    public func currentSpeedLimitResult(near coordinate: GuidanceCoordinate) async throws -> OSMSpeedLimitResult? {
        let coordinateKey = OSMSpeedLimitCacheKey.coordinateCorridor(SpeedLimitSegmentCacheKey(coordinate: coordinate))
        if let cached = cachedResult(for: coordinateKey) {
            return cached
        }

        let query = Self.overpassQuery(near: coordinate)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = query.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await session.data(for: request)
        guard let result = Self.parseSpeedLimitResult(from: data, coordinate: coordinate, minimumConfidence: minimumConfidence) else {
            return nil
        }

        let entry = OSMSpeedLimitCacheEntry(
            speedLimitMPH: result.currentSpeedLimitMPH,
            confidence: result.confidence,
            roadName: result.roadName,
            wayId: result.wayId,
            source: result.source
        )
        cache[coordinateKey] = entry

        if let wayId = result.wayId {
            cache[.wayId(wayId)] = entry
        }

        return result
    }

    public func cachedResult(for key: OSMSpeedLimitCacheKey, now: Date = Date()) -> OSMSpeedLimitResult? {
        guard let entry = cache[key] else { return nil }
        let ttl = entry.wayId != nil ? wayCacheTTL : coordinateCacheTTL
        guard now.timeIntervalSince(entry.timestamp) <= ttl else {
            cache[key] = nil
            return nil
        }

        return entry.result
    }

    public func storeCachedResult(_ result: OSMSpeedLimitResult, for coordinate: GuidanceCoordinate, timestamp: Date = Date()) {
        let entry = OSMSpeedLimitCacheEntry(
            speedLimitMPH: result.currentSpeedLimitMPH,
            confidence: result.confidence,
            roadName: result.roadName,
            wayId: result.wayId,
            source: result.source,
            timestamp: timestamp
        )
        cache[.coordinateCorridor(SpeedLimitSegmentCacheKey(coordinate: coordinate))] = entry
        if let wayId = result.wayId {
            cache[.wayId(wayId)] = entry
        }
    }

    public static func overpassQuery(near coordinate: GuidanceCoordinate, radiusMeters: Int = 45) -> String {
        """
        [out:json][timeout:8];
        way(around:\(radiusMeters),\(coordinate.latitude),\(coordinate.longitude))[highway];
        out tags center geom 8;
        """
    }

    public static func parseSpeedLimitEstimate(from data: Data) -> SpeedLimitEstimate {
        guard let result = parseSpeedLimitResult(from: data) else {
            return .unavailable(reason: "No confident OpenStreetMap speed-limit estimate near current road.")
        }

        return .estimate(result.speedLimitValue)
    }

    public static func parseSpeedLimitResult(
        from data: Data,
        coordinate: GuidanceCoordinate? = nil,
        minimumConfidence: Double = 0.55
    ) -> OSMSpeedLimitResult? {
        guard let response = try? JSONDecoder().decode(OSMOverpassResponse.self, from: data) else {
            return nil
        }

        let candidates = response.elements.compactMap { element -> (element: OSMElement, speedLimitMPH: Int, confidence: Double)? in
            guard
                let maxspeed = element.tags?.maxspeed,
                let speedLimitMPH = parseMaxspeedMilesPerHour(maxspeed)
            else {
                return nil
            }

            let confidence = confidence(for: element, coordinate: coordinate)
            return (element, speedLimitMPH, confidence)
        }
        .sorted {
            $0.confidence == $1.confidence
                ? ($0.element.tags?.name ?? "") < ($1.element.tags?.name ?? "")
                : $0.confidence > $1.confidence
        }

        guard let best = candidates.first, best.confidence >= minimumConfidence else {
            return nil
        }

        return OSMSpeedLimitResult(
            currentSpeedLimitMPH: best.speedLimitMPH,
            confidence: best.confidence,
            roadName: best.element.tags?.name,
            wayId: best.element.id
        )
    }

    public static func parseMaxspeedMilesPerHour(_ rawValue: String) -> Int? {
        let lowercased = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return nil }

        if lowercased.contains("mph") {
            return firstNumber(in: lowercased).map { Int($0.rounded()) }
        }

        if lowercased.contains("signals") || lowercased.contains("walk") || lowercased.contains("none") {
            return nil
        }

        guard let kilometersPerHour = firstNumber(in: lowercased) else { return nil }
        return Int((kilometersPerHour * 0.621371).rounded())
    }

    private static func confidence(for element: OSMElement, coordinate: GuidanceCoordinate?) -> Double {
        guard let coordinate else { return 0.7 }
        let distances = element.geometry?.map {
            coordinate.location.distance(from: GuidanceCoordinate(latitude: $0.lat, longitude: $0.lon).location)
        } ?? []
        let centerDistance = element.center.map {
            coordinate.location.distance(from: GuidanceCoordinate(latitude: $0.lat, longitude: $0.lon).location)
        }

        guard let nearestDistance = (distances + [centerDistance].compactMap { $0 }).min() else {
            return 0.6
        }

        switch nearestDistance {
        case ...20:
            return 0.95
        case ...40:
            return 0.78
        case ...70:
            return 0.58
        default:
            return 0.35
        }
    }

    private static func firstNumber(in string: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }

        return Double(string[range])
    }
}

private struct OSMOverpassResponse: Decodable {
    var elements: [OSMElement]
}

private struct OSMElement: Decodable {
    var id: Int64?
    var tags: OSMTags?
    var center: OSMCoordinate?
    var geometry: [OSMCoordinate]?
}

private struct OSMTags: Decodable {
    var name: String?
    var maxspeed: String?
}

private struct OSMCoordinate: Decodable {
    var lat: Double
    var lon: Double
}
