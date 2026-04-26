import CoreLocation
import Foundation
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
    public var source: String

    public init(
        summary: String,
        temperatureCelsius: Double? = nil,
        precipitationChance: Double? = nil,
        windDescription: String? = nil,
        alertStatus: String? = nil,
        source: String = "WeatherKit"
    ) {
        self.summary = summary
        self.temperatureCelsius = temperatureCelsius
        self.precipitationChance = precipitationChance
        self.windDescription = windDescription
        self.alertStatus = alertStatus
        self.source = source
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

public enum WeatherRouteProviderError: Error, Equatable {
    case insufficientRouteGeometry
    case forecastUnavailable
}

public protocol RouteWeatherForecastClient: Sendable {
    func forecast(for checkpoint: RouteWeatherCheckpoint) async throws -> RouteWeatherForecast
}

public struct UnavailableRouteWeatherForecastClient: RouteWeatherForecastClient {
    public init() {}

    public func forecast(for checkpoint: RouteWeatherCheckpoint) async throws -> RouteWeatherForecast {
        throw WeatherRouteProviderError.forecastUnavailable
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
        let weather = try await WeatherService.shared.weather(for: checkpoint.coordinate.location)
        let arrival = checkpoint.expectedArrivalDate
        let hourlyForecast = weather.hourlyForecast.forecast.min {
            abs($0.date.timeIntervalSince(arrival)) < abs($1.date.timeIntervalSince(arrival))
        }

        if let hourlyForecast {
            return RouteWeatherForecast(
                summary: "Expected around arrival: \(hourlyForecast.condition.description)",
                temperatureCelsius: hourlyForecast.temperature.converted(to: .celsius).value,
                precipitationChance: hourlyForecast.precipitationChance,
                windDescription: "\(Int(hourlyForecast.wind.speed.converted(to: .milesPerHour).value.rounded())) mph",
                alertStatus: weather.weatherAlerts?.isEmpty == false ? "Weather alert nearby" : nil,
                source: "WeatherKit"
            )
        }

        return RouteWeatherForecast(
            summary: "Expected around arrival: \(weather.currentWeather.condition.description)",
            temperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
            precipitationChance: nil,
            windDescription: "\(Int(weather.currentWeather.wind.speed.converted(to: .milesPerHour).value.rounded())) mph",
            alertStatus: weather.weatherAlerts?.isEmpty == false ? "Weather alert nearby" : nil,
            source: "WeatherKit"
        )
    }
}
#endif
