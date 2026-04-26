import CoreLocation
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif

public struct RouteWeatherCheckpoint: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var coordinate: GuidanceCoordinate
    public var distanceFromStartMeters: Double
    public var expectedArrivalDate: Date

    public init(
        id: UUID = UUID(),
        coordinate: GuidanceCoordinate,
        distanceFromStartMeters: Double,
        expectedArrivalDate: Date
    ) {
        self.id = id
        self.coordinate = coordinate
        self.distanceFromStartMeters = distanceFromStartMeters
        self.expectedArrivalDate = expectedArrivalDate
    }
}

public struct RouteWeatherForecast: Equatable, Sendable {
    public var summary: String
    public var temperatureCelsius: Double?
    public var precipitationChance: Double?
    public var windDescription: String?
    public var alertStatus: String?
    public var advisories: [RouteWeatherAdvisory]
    public var source: String

    public init(
        summary: String,
        temperatureCelsius: Double? = nil,
        precipitationChance: Double? = nil,
        windDescription: String? = nil,
        alertStatus: String? = nil,
        advisories: [RouteWeatherAdvisory] = [],
        source: String = "WeatherKit"
    ) {
        self.summary = summary
        self.temperatureCelsius = temperatureCelsius
        self.precipitationChance = precipitationChance
        self.windDescription = windDescription
        self.alertStatus = alertStatus
        self.advisories = advisories
        self.source = source
    }
}

public struct RouteWeatherAdvisory: Equatable, Sendable {
    public var title: String
    public var summary: String?
    public var affectedArea: String?
    public var issuedAt: Date?
    public var source: String?
    public var sourceURL: URL?

    public init(
        title: String,
        summary: String? = nil,
        affectedArea: String? = nil,
        issuedAt: Date? = nil,
        source: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.title = title
        self.summary = summary
        self.affectedArea = affectedArea
        self.issuedAt = issuedAt
        self.source = source
        self.sourceURL = sourceURL
    }
}

public struct RouteWeatherTimelineEntry: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var checkpoint: RouteWeatherCheckpoint
    public var forecast: RouteWeatherForecast

    public init(
        id: UUID = UUID(),
        checkpoint: RouteWeatherCheckpoint,
        forecast: RouteWeatherForecast
    ) {
        self.id = id
        self.checkpoint = checkpoint
        self.forecast = forecast
    }
}

public enum WeatherRouteProviderError: Error, Equatable, LocalizedError, Sendable {
    case insufficientRouteGeometry
    case weatherKitNotConfigured
    case forecastUnavailable
    case weatherKitRequestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .insufficientRouteGeometry:
            return "Route geometry did not include enough points for route weather checkpoints."
        case .weatherKitNotConfigured:
            return "WeatherKit is not configured for this build."
        case .forecastUnavailable:
            return "Weather forecast data is unavailable for this route."
        case .weatherKitRequestFailed(let reason):
            return reason
        }
    }
}

public protocol RouteWeatherForecastClient: Sendable {
    func forecast(for checkpoint: RouteWeatherCheckpoint) async throws -> RouteWeatherForecast
}

public struct UnavailableRouteWeatherForecastClient: RouteWeatherForecastClient {
    public init() {}

    public func forecast(for checkpoint: RouteWeatherCheckpoint) async throws -> RouteWeatherForecast {
        throw WeatherRouteProviderError.weatherKitNotConfigured
    }
}

public final class WeatherRouteProvider: Sendable {
    private let forecastClient: any RouteWeatherForecastClient

    public init(forecastClient: any RouteWeatherForecastClient = UnavailableRouteWeatherForecastClient()) {
        self.forecastClient = forecastClient
    }

    public func checkpoints(
        for routeGeometry: [GuidanceCoordinate],
        routeDistanceMeters: Double,
        startDate: Date,
        expectedTravelTimeSeconds: TimeInterval,
        maxCheckpointCount: Int = 6
    ) throws -> [RouteWeatherCheckpoint] {
        guard routeGeometry.count >= 2 else {
            throw WeatherRouteProviderError.insufficientRouteGeometry
        }

        let measuredDistances = Self.cumulativeDistances(for: routeGeometry)
        let totalDistance = routeDistanceMeters > 0 ? routeDistanceMeters : (measuredDistances.last ?? 0)
        guard totalDistance > 0 else {
            throw WeatherRouteProviderError.insufficientRouteGeometry
        }

        let checkpointCount = min(max(maxCheckpointCount, 2), 8)
        let targets = (0..<checkpointCount).map { index in
            totalDistance * (Double(index + 1) / Double(checkpointCount))
        }

        return targets.compactMap { targetDistance in
            guard let coordinate = Self.interpolateCoordinate(
                routeGeometry: routeGeometry,
                cumulativeDistances: measuredDistances,
                targetDistance: targetDistance
            ) else {
                return nil
            }

            let progress = min(max(targetDistance / totalDistance, 0), 1)
            return RouteWeatherCheckpoint(
                coordinate: coordinate,
                distanceFromStartMeters: targetDistance,
                expectedArrivalDate: startDate.addingTimeInterval(expectedTravelTimeSeconds * progress)
            )
        }
    }

    public func timeline(
        for checkpoints: [RouteWeatherCheckpoint]
    ) async throws -> [RouteWeatherTimelineEntry] {
        try await withThrowingTaskGroup(of: RouteWeatherTimelineEntry.self) { group in
            for checkpoint in checkpoints {
                group.addTask { [forecastClient] in
                    let forecast = try await forecastClient.forecast(for: checkpoint)
                    return RouteWeatherTimelineEntry(checkpoint: checkpoint, forecast: forecast)
                }
            }

            var entries: [RouteWeatherTimelineEntry] = []
            for try await entry in group {
                entries.append(entry)
            }

            return entries.sorted {
                $0.checkpoint.distanceFromStartMeters < $1.checkpoint.distanceFromStartMeters
            }
        }
    }

    public func timeline(
        routeGeometry: [GuidanceCoordinate],
        routeDistanceMeters: Double,
        startDate: Date,
        expectedTravelTimeSeconds: TimeInterval,
        maxCheckpointCount: Int = 6
    ) async throws -> [RouteWeatherTimelineEntry] {
        let checkpoints = try checkpoints(
            for: routeGeometry,
            routeDistanceMeters: routeDistanceMeters,
            startDate: startDate,
            expectedTravelTimeSeconds: expectedTravelTimeSeconds,
            maxCheckpointCount: maxCheckpointCount
        )
        return try await timeline(for: checkpoints)
    }

    private static func cumulativeDistances(for geometry: [GuidanceCoordinate]) -> [Double] {
        var distances: [Double] = [0]
        guard geometry.count > 1 else { return distances }

        for index in 1..<geometry.count {
            let previous = geometry[index - 1].location
            let current = geometry[index].location
            distances.append((distances.last ?? 0) + previous.distance(from: current))
        }

        return distances
    }

    private static func interpolateCoordinate(
        routeGeometry: [GuidanceCoordinate],
        cumulativeDistances: [Double],
        targetDistance: Double
    ) -> GuidanceCoordinate? {
        guard routeGeometry.count == cumulativeDistances.count,
              let totalDistance = cumulativeDistances.last,
              totalDistance > 0 else {
            return nil
        }

        let clampedTarget = min(max(targetDistance, 0), totalDistance)
        guard let upperIndex = cumulativeDistances.firstIndex(where: { $0 >= clampedTarget }) else {
            return routeGeometry.last
        }

        if upperIndex == 0 {
            return routeGeometry.first
        }

        let lowerIndex = upperIndex - 1
        let lowerDistance = cumulativeDistances[lowerIndex]
        let upperDistance = cumulativeDistances[upperIndex]
        let segmentDistance = max(upperDistance - lowerDistance, 0.0001)
        let fraction = (clampedTarget - lowerDistance) / segmentDistance

        let lower = routeGeometry[lowerIndex]
        let upper = routeGeometry[upperIndex]
        return GuidanceCoordinate(
            latitude: lower.latitude + (upper.latitude - lower.latitude) * fraction,
            longitude: lower.longitude + (upper.longitude - lower.longitude) * fraction
        )
    }
}

#if canImport(WeatherKit)
@available(iOS 16.0, macOS 13.0, *)
public struct WeatherKitRouteWeatherForecastClient: RouteWeatherForecastClient {
    public init() {}

    public func forecast(for checkpoint: RouteWeatherCheckpoint) async throws -> RouteWeatherForecast {
        let arrival = checkpoint.expectedArrivalDate
        Self.logRequest(checkpoint: checkpoint)

        let weather: Weather
        do {
            weather = try await WeatherService.shared.weather(for: checkpoint.coordinate.location)
        } catch {
            let reason = Self.requestFailureReason(from: error)
            Self.logFailure(checkpoint: checkpoint, error: error, reason: reason)
            throw WeatherRouteProviderError.weatherKitRequestFailed(reason)
        }

        let hourlyForecast = weather.hourlyForecast.forecast.min {
            abs($0.date.timeIntervalSince(arrival)) < abs($1.date.timeIntervalSince(arrival))
        }
        let advisories = Self.routeAdvisories(from: weather)

        if let hourlyForecast {
            Self.logSuccess(checkpoint: checkpoint, usedHourlyForecast: true)
            return RouteWeatherForecast(
                summary: "Expected around arrival: \(hourlyForecast.condition.description)",
                temperatureCelsius: hourlyForecast.temperature.converted(to: .celsius).value,
                precipitationChance: hourlyForecast.precipitationChance,
                windDescription: "\(Int(hourlyForecast.wind.speed.converted(to: .milesPerHour).value.rounded())) mph",
                alertStatus: advisories.first?.title,
                advisories: advisories,
                source: "WeatherKit"
            )
        }

        Self.logSuccess(checkpoint: checkpoint, usedHourlyForecast: false)
        return RouteWeatherForecast(
            summary: "Expected around arrival: \(weather.currentWeather.condition.description)",
            temperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
            precipitationChance: nil,
            windDescription: "\(Int(weather.currentWeather.wind.speed.converted(to: .milesPerHour).value.rounded())) mph",
            alertStatus: advisories.first?.title,
            advisories: advisories,
            source: "WeatherKit"
        )
    }

    private static func requestFailureReason(from error: Error) -> String {
        let nsError = error as NSError
        let description = error.localizedDescription
        let diagnosticText = "\(nsError.domain) \(nsError.code) \(description)".lowercased()

        if diagnosticText.contains("weatherdaemon") ||
            diagnosticText.contains("wdsjwt") ||
            diagnosticText.contains("authenticator") ||
            diagnosticText.contains("jwt") ||
            diagnosticText.contains("signature") ||
            diagnosticText.contains("provisioning") ||
            diagnosticText.contains("app identifier") ||
            diagnosticText.contains("bundle identifier") ||
            diagnosticText.contains("team id") ||
            diagnosticText.contains("entitlement") ||
            diagnosticText.contains("not authorized") ||
            diagnosticText.contains("authorization") {
            return "WeatherKit is not available for this signed build. Check the WeatherKit capability and provisioning profile."
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "WeatherKit network request failed. Check the connection and try the route forecast again."
            default:
                break
            }
        }

        if description.isEmpty {
            return "WeatherKit request failed for this route checkpoint."
        }

        if diagnosticText.contains("weatherkit") {
            return "WeatherKit request failed. Check the signed entitlement, device capability, provider availability, and route checkpoint data."
        }

        return "WeatherKit request failed: \(description)"
    }

    private static func routeAdvisories(from weather: Weather) -> [RouteWeatherAdvisory] {
        guard weather.weatherAlerts?.isEmpty == false else { return [] }
        return [
            RouteWeatherAdvisory(
                title: "Weather advisory nearby",
                summary: "WeatherKit reports an active advisory near this checkpoint.",
                source: "WeatherKit"
            )
        ]
    }

    private static func logRequest(checkpoint: RouteWeatherCheckpoint) {
        #if canImport(OSLog)
        logger.debug(
            "WeatherKit request checkpoint lat=\(checkpoint.coordinate.latitude, privacy: .private) lon=\(checkpoint.coordinate.longitude, privacy: .private) arrival=\(checkpoint.expectedArrivalDate.timeIntervalSince1970, privacy: .public)"
        )
        #endif
    }

    private static func logSuccess(checkpoint: RouteWeatherCheckpoint, usedHourlyForecast: Bool) {
        #if canImport(OSLog)
        logger.debug(
            "WeatherKit forecast resolved checkpoint=\(checkpoint.id.uuidString, privacy: .public) hourly=\(usedHourlyForecast, privacy: .public)"
        )
        #endif
    }

    private static func logFailure(checkpoint: RouteWeatherCheckpoint, error: Error, reason: String) {
        #if canImport(OSLog)
        logger.error(
            "WeatherKit request failed checkpoint=\(checkpoint.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public) reason=\(reason, privacy: .public)"
        )
        #endif
    }

    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.timethrottle.app", category: "WeatherKit")
    #endif
}
#endif
