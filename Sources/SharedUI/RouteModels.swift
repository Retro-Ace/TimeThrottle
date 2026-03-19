import Foundation
@preconcurrency import MapKit

public struct RouteCoordinate: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum TripCompareEntryStyle: String, CaseIterable, Identifiable {
    case averageSpeed = "Average speed"
    case tripDuration = "Trip duration"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .averageSpeed:
            return "Enter the whole-trip average speed and compare it to the baseline pace."
        case .tripDuration:
            return "Enter the whole-trip duration and derive the average speed from distance and time."
        }
    }
}

enum TripCompareDistanceSource: String, CaseIterable, Identifiable {
    case appleMapsRoute = "Apple Maps route"
    case manualMiles = "Manual miles"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .manualMiles:
            return "Enter a posted speed limit and route distance by hand."
        case .appleMapsRoute:
            return "Look up a route by address and use Apple Maps distance and ETA as the baseline."
        }
    }
}

public enum Mode: String, CaseIterable, Identifiable, Sendable {
    case liveDrive = "Live Drive"
    case route = "Route"
    case manual = "Manual"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .liveDrive:
            return "Track a drive live with GPS speed, distance, and trip analysis."
        case .route:
            return "Compare a trip against an Apple Maps route distance and ETA."
        case .manual:
            return "Compare a trip against a hand-entered route distance and target speed."
        }
    }

    var tripCompareDistanceSource: TripCompareDistanceSource? {
        switch self {
        case .liveDrive:
            return nil
        case .route:
            return .appleMapsRoute
        case .manual:
            return .manualMiles
        }
    }
}

public struct RouteComparisonConfiguration: Equatable, Sendable {
    public var initialMode: Mode

    public init(initialMode: Mode = .liveDrive) {
        self.initialMode = initialMode
    }
}

public enum RouteLookupError: LocalizedError {
    case blankAddress(String)
    case noResults(String)
    case noRoute

    public var errorDescription: String? {
        switch self {
        case .blankAddress(let label):
            return "Enter a \(label) address."
        case .noResults(let query):
            return "Apple Maps could not find \"\(query)\"."
        case .noRoute:
            return "Apple Maps found the addresses but could not build a driving route."
        }
    }
}

public struct RouteEstimate: Identifiable, Sendable {
    public var id: UUID
    public var sourceQuery: String
    public var destinationQuery: String
    public var sourceName: String
    public var destinationName: String
    public var sourceCoordinate: RouteCoordinate
    public var destinationCoordinate: RouteCoordinate
    public var distanceMiles: Double
    public var expectedTravelMinutes: Double
    public var routeName: String
    public var routeCoordinates: [RouteCoordinate]
    public var advisories: [String]

    public init(
        id: UUID,
        sourceQuery: String,
        destinationQuery: String,
        sourceName: String,
        destinationName: String,
        sourceCoordinate: RouteCoordinate,
        destinationCoordinate: RouteCoordinate,
        distanceMiles: Double,
        expectedTravelMinutes: Double,
        routeName: String,
        routeCoordinates: [RouteCoordinate],
        advisories: [String]
    ) {
        self.id = id
        self.sourceQuery = sourceQuery
        self.destinationQuery = destinationQuery
        self.sourceName = sourceName
        self.destinationName = destinationName
        self.sourceCoordinate = sourceCoordinate
        self.destinationCoordinate = destinationCoordinate
        self.distanceMiles = distanceMiles
        self.expectedTravelMinutes = expectedTravelMinutes
        self.routeName = routeName
        self.routeCoordinates = routeCoordinates
        self.advisories = advisories
    }
}

enum RouteFormatter {
    static func displayName(for item: MKMapItem, fallback: String) -> String {
        let parts = [
            item.name,
            item.placemark.locality,
            item.placemark.administrativeArea
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        if parts.isEmpty {
            return fallback
        }

        return parts.joined(separator: ", ")
    }
}

enum RouteGeometry {
    static func coordinates(from route: MKRoute) -> [RouteCoordinate] {
        let polyline = route.polyline
        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))

        return coordinates.map { coordinate in
            RouteCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}

enum RouteLookupService {
    static func fetchRouteOptions(
        sourceQuery: String,
        destinationQuery: String
    ) async throws -> [RouteEstimate] {
        try await withCheckedThrowingContinuation { continuation in
            let sourceSearchRequest = MKLocalSearch.Request()
            sourceSearchRequest.naturalLanguageQuery = sourceQuery

            MKLocalSearch(request: sourceSearchRequest).start { sourceResponse, sourceError in
                if let sourceError {
                    continuation.resume(throwing: sourceError)
                    return
                }

                guard let sourceItem = sourceResponse?.mapItems.first else {
                    continuation.resume(throwing: RouteLookupError.noResults(sourceQuery))
                    return
                }

                let destinationSearchRequest = MKLocalSearch.Request()
                destinationSearchRequest.naturalLanguageQuery = destinationQuery

                MKLocalSearch(request: destinationSearchRequest).start { destinationResponse, destinationError in
                    if let destinationError {
                        continuation.resume(throwing: destinationError)
                        return
                    }

                    guard let destinationItem = destinationResponse?.mapItems.first else {
                        continuation.resume(throwing: RouteLookupError.noResults(destinationQuery))
                        return
                    }

                    let directionsRequest = MKDirections.Request()
                    directionsRequest.source = sourceItem
                    directionsRequest.destination = destinationItem
                    directionsRequest.transportType = .automobile
                    directionsRequest.requestsAlternateRoutes = true

                    MKDirections(request: directionsRequest).calculate { response, directionsError in
                        if let directionsError {
                            continuation.resume(throwing: directionsError)
                            return
                        }

                        guard let routes = response?.routes, !routes.isEmpty else {
                            continuation.resume(throwing: RouteLookupError.noRoute)
                            return
                        }

                        let estimates = routes
                            .sorted {
                                if $0.expectedTravelTime == $1.expectedTravelTime {
                                    return $0.distance < $1.distance
                                }
                                return $0.expectedTravelTime < $1.expectedTravelTime
                            }
                            .map { route in
                                RouteEstimate(
                                    id: UUID(),
                                    sourceQuery: sourceQuery,
                                    destinationQuery: destinationQuery,
                                    sourceName: RouteFormatter.displayName(for: sourceItem, fallback: sourceQuery),
                                    destinationName: RouteFormatter.displayName(for: destinationItem, fallback: destinationQuery),
                                    sourceCoordinate: RouteCoordinate(
                                        latitude: sourceItem.placemark.coordinate.latitude,
                                        longitude: sourceItem.placemark.coordinate.longitude
                                    ),
                                    destinationCoordinate: RouteCoordinate(
                                        latitude: destinationItem.placemark.coordinate.latitude,
                                        longitude: destinationItem.placemark.coordinate.longitude
                                    ),
                                    distanceMiles: route.distance / 1_609.344,
                                    expectedTravelMinutes: route.expectedTravelTime / 60,
                                    routeName: route.name,
                                    routeCoordinates: RouteGeometry.coordinates(from: route),
                                    advisories: route.advisoryNotices
                                )
                            }

                        continuation.resume(returning: estimates)
                    }
                }
            }
        }
    }
}

public extension MKCoordinateRegion {
    init(_ coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else {
            self = MKCoordinateRegion()
            return
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let latitudeDelta = max((maxLatitude - minLatitude) * 1.35, 1.0)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.35, 1.0)

        self = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}
