import Foundation

public actor OSMSpeedLimitProvider: SpeedLimitProvider {
    private let service: OSMSpeedLimitService

    public init(
        endpoint: URL = URL(string: "https://overpass-api.de/api/interpreter")!,
        session: URLSession = .shared
    ) {
        self.service = OSMSpeedLimitService(endpoint: endpoint, session: session)
    }

    public func currentSpeedLimit(near coordinate: GuidanceCoordinate) async throws -> SpeedLimitEstimate {
        try await service.currentSpeedLimit(near: coordinate)
    }

    public func cachedEstimate(near coordinate: GuidanceCoordinate) async -> SpeedLimitEstimate? {
        let key = OSMSpeedLimitCacheKey.coordinateCorridor(SpeedLimitSegmentCacheKey(coordinate: coordinate))
        guard let result = await service.cachedResult(for: key) else { return nil }
        return .estimate(result.speedLimitValue)
    }

    public static func overpassQuery(near coordinate: GuidanceCoordinate, radiusMeters: Int = 45) -> String {
        OSMSpeedLimitService.overpassQuery(near: coordinate, radiusMeters: radiusMeters)
    }

    public static func parseSpeedLimitEstimate(from data: Data) -> SpeedLimitEstimate {
        OSMSpeedLimitService.parseSpeedLimitEstimate(from: data)
    }

    public static func parseSpeedLimitResult(
        from data: Data,
        coordinate: GuidanceCoordinate? = nil,
        minimumConfidence: Double = 0.55
    ) -> OSMSpeedLimitResult? {
        OSMSpeedLimitService.parseSpeedLimitResult(
            from: data,
            coordinate: coordinate,
            minimumConfidence: minimumConfidence
        )
    }

    public static func parseMaxspeedMilesPerHour(_ rawValue: String) -> Int? {
        OSMSpeedLimitService.parseMaxspeedMilesPerHour(rawValue)
    }
}
