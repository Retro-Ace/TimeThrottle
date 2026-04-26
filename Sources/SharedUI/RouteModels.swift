import Combine
import CoreLocation
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

public enum NavigationProvider: String, CaseIterable, Identifiable, Sendable {
    case appleMaps = "Apple Maps"
    case googleMaps = "Google Maps"
    case waze = "Waze"
    case askEveryTime = "Ask Every Time"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .appleMaps:
            return "Open Apple Maps directions after TimeThrottle starts tracking."
        case .googleMaps:
            return "Open Google Maps if it is installed, otherwise fall back to the web route."
        case .waze:
            return "Open Waze if it is installed, otherwise fall back to the web route."
        case .askEveryTime:
            return "Choose Apple Maps, Google Maps, or Waze when a Live Drive starts."
        }
    }
}

public enum LiveDriveMapMode: String, CaseIterable, Identifiable, Sendable {
    case standard = "Standard"
    case satellite = "Satellite"

    public var id: String { rawValue }
}

enum RouteOriginInputMode: String, CaseIterable, Identifiable {
    case currentLocation = "Current Location"
    case custom = "Custom"

    var id: String { rawValue }
}

enum RouteAddressField: Hashable {
    case from
    case to
}

public struct ResolvedRoutePlace: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var query: String
    public var coordinate: RouteCoordinate
    public var isCurrentLocation: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        query: String,
        coordinate: RouteCoordinate,
        isCurrentLocation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.query = query
        self.coordinate = coordinate
        self.isCurrentLocation = isCurrentLocation
    }

    public var displayText: String {
        if isCurrentLocation {
            return title
        }

        if subtitle.isEmpty {
            return title
        }

        return "\(title), \(subtitle)"
    }

    public var detailText: String {
        if subtitle.isEmpty {
            return title
        }

        return "\(title), \(subtitle)"
    }
}

struct RouteLookupEndpoint: Equatable, Sendable {
    let signature: String
    let query: String
    let displayName: String
    let coordinate: RouteCoordinate?
    let isCurrentLocation: Bool

    static func query(_ query: String) -> RouteLookupEndpoint {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return RouteLookupEndpoint(
            signature: "query:\(normalized)",
            query: query,
            displayName: query,
            coordinate: nil,
            isCurrentLocation: false
        )
    }

    static func resolvedPlace(_ place: ResolvedRoutePlace) -> RouteLookupEndpoint {
        let normalized = place.displayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return RouteLookupEndpoint(
            signature: "place:\(normalized):\(place.coordinate.latitude),\(place.coordinate.longitude)",
            query: place.query,
            displayName: place.detailText,
            coordinate: place.coordinate,
            isCurrentLocation: false
        )
    }

    static func currentLocation(_ place: ResolvedRoutePlace) -> RouteLookupEndpoint {
        RouteLookupEndpoint(
            signature: "current:\(place.coordinate.latitude),\(place.coordinate.longitude)",
            query: place.query,
            displayName: place.detailText,
            coordinate: place.coordinate,
            isCurrentLocation: true
        )
    }
}

@MainActor
final class AppleMapsAutocompleteController: NSObject, ObservableObject {
    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion

        var displayText: String {
            if subtitle.isEmpty {
                return title
            }

            return "\(title), \(subtitle)"
        }
    }

    @Published private(set) var activeField: RouteAddressField?
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String, for field: RouteAddressField) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeField = field

        guard trimmed.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }

        isSearching = true
        completer.queryFragment = trimmed
    }

    func clear(field: RouteAddressField? = nil) {
        if field == nil || activeField == field {
            activeField = nil
            suggestions = []
            isSearching = false
        }
    }

    func resolve(_ suggestion: Suggestion) async throws -> ResolvedRoutePlace {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let item = response.mapItems.first else {
            throw RouteLookupError.noResults(suggestion.displayText)
        }

        return ResolvedRoutePlace(
            title: item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? suggestion.title,
            subtitle: Self.subtitle(for: item.placemark, fallback: suggestion.subtitle),
            query: suggestion.displayText,
            coordinate: RouteCoordinate(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
        )
    }

    private static func subtitle(for placemark: MKPlacemark, fallback: String) -> String {
        let parts = [
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }

        if parts.isEmpty {
            return fallback
        }

        return parts.joined(separator: ", ")
    }
}

extension AppleMapsAutocompleteController: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let suggestions = completer.results
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(6)
            .map { completion in
                Suggestion(
                    title: completion.title,
                    subtitle: completion.subtitle,
                    completion: completion
                )
            }

        Task { @MainActor [weak self] in
            self?.suggestions = Array(suggestions)
            self?.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.suggestions = []
            self?.isSearching = false
        }
    }
}

@MainActor
final class CurrentLocationResolver: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentPlace: ResolvedRoutePlace?
    @Published private(set) var isResolving = false
    @Published private(set) var errorMessage: String?

    private let geocoder = CLGeocoder()
    private let locationManager: CLLocationManager
    private var hasPendingRequest = false

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocationIfNeeded() {
        if currentPlace != nil || isResolving {
            return
        }

        requestCurrentLocation()
    }

    func requestCurrentLocation() {
        errorMessage = nil
        hasPendingRequest = true

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isResolving = true
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            isResolving = false
            errorMessage = "Location access is off. Enable location access in Settings to use Current Location."
        case .restricted:
            isResolving = false
            errorMessage = "Current Location is unavailable because location access is restricted."
        @unknown default:
            isResolving = false
            errorMessage = "Current Location is unavailable right now."
        }
    }

    func refreshAuthorizationState() {
        authorizationStatus = locationManager.authorizationStatus
    }

    private func update(with location: CLLocation) {
        Task {
            let place = await reverseGeocodedPlace(for: location)
            currentPlace = place
            isResolving = false
            errorMessage = nil
            hasPendingRequest = false
        }
    }

    private func reverseGeocodedPlace(for location: CLLocation) async -> ResolvedRoutePlace {
        let coordinate = RouteCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let subtitleParts = [
                    placemark.locality,
                    placemark.administrativeArea
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }

                return ResolvedRoutePlace(
                    title: "Current Location",
                    subtitle: subtitleParts.joined(separator: ", "),
                    query: "Current Location",
                    coordinate: coordinate,
                    isCurrentLocation: true
                )
            }
        } catch {
            // Fall back to the coordinate-only label below.
        }

        return ResolvedRoutePlace(
            title: "Current Location",
            query: "Current Location",
            coordinate: coordinate,
            isCurrentLocation: true
        )
    }
}

extension CurrentLocationResolver: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.authorizationStatus = status

            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.hasPendingRequest {
                    self.isResolving = true
                    self.locationManager.requestLocation()
                }
            case .denied:
                self.isResolving = false
                self.errorMessage = "Location access is off. Enable location access in Settings to use Current Location."
            case .restricted:
                self.isResolving = false
                self.errorMessage = "Current Location is unavailable because location access is restricted."
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor [weak self] in
                self?.isResolving = false
                self?.hasPendingRequest = false
            }
            return
        }

        Task { @MainActor [weak self] in
            self?.update(with: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isResolving = false
            self?.hasPendingRequest = false
            self?.errorMessage = "Current Location is unavailable right now. Refresh Current Location or try again."
        }
    }
}

public struct RouteComparisonConfiguration: Equatable, Sendable {
    public init() {}
}

public enum RouteLookupError: LocalizedError {
    case blankAddress(String)
    case currentLocationUnavailable
    case noResults(String)
    case noRoute

    public var errorDescription: String? {
        switch self {
        case .blankAddress(let label):
            return "Enter a \(label) address."
        case .currentLocationUnavailable:
            return "Current Location is not ready yet. Wait for the location fix or refresh Current Location."
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
    public var destinationTimeZoneIdentifier: String?
    public var sourceCoordinate: RouteCoordinate
    public var destinationCoordinate: RouteCoordinate
    public var distanceMiles: Double
    public var expectedTravelMinutes: Double
    public var routeName: String
    public var routeCoordinates: [RouteCoordinate]
    public var maneuverSteps: [RouteManeuverStep]
    public var advisories: [String]

    public init(
        id: UUID,
        sourceQuery: String,
        destinationQuery: String,
        sourceName: String,
        destinationName: String,
        destinationTimeZoneIdentifier: String? = nil,
        sourceCoordinate: RouteCoordinate,
        destinationCoordinate: RouteCoordinate,
        distanceMiles: Double,
        expectedTravelMinutes: Double,
        routeName: String,
        routeCoordinates: [RouteCoordinate],
        maneuverSteps: [RouteManeuverStep] = [],
        advisories: [String]
    ) {
        self.id = id
        self.sourceQuery = sourceQuery
        self.destinationQuery = destinationQuery
        self.sourceName = sourceName
        self.destinationName = destinationName
        self.destinationTimeZoneIdentifier = destinationTimeZoneIdentifier
        self.sourceCoordinate = sourceCoordinate
        self.destinationCoordinate = destinationCoordinate
        self.distanceMiles = distanceMiles
        self.expectedTravelMinutes = expectedTravelMinutes
        self.routeName = routeName
        self.routeCoordinates = routeCoordinates
        self.maneuverSteps = maneuverSteps
        self.advisories = advisories
    }

    public var destinationTimeZone: TimeZone? {
        guard let destinationTimeZoneIdentifier else { return nil }
        return TimeZone(identifier: destinationTimeZoneIdentifier)
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

    static func maneuverSteps(from route: MKRoute) -> [RouteManeuverStep] {
        route.steps.map { step in
            let instruction = step.instructions
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? "Continue on route"

            return RouteManeuverStep(
                instruction: instruction,
                distanceMeters: step.distance,
                geometry: guidanceCoordinates(from: step.polyline),
                transportType: RouteStepTransportType(mapKitType: step.transportType)
            )
        }
    }

    private static func guidanceCoordinates(from polyline: MKPolyline) -> [GuidanceCoordinate] {
        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))

        return coordinates.map { coordinate in
            GuidanceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}

enum RouteLookupService {
    static func fetchRouteOptions(
        sourceQuery: String,
        destinationQuery: String
    ) async throws -> [RouteEstimate] {
        try await fetchRouteOptions(
            source: .query(sourceQuery),
            destination: .query(destinationQuery)
        )
    }

    static func fetchRouteOptions(
        source: RouteLookupEndpoint,
        destination: RouteLookupEndpoint
    ) async throws -> [RouteEstimate] {
        let sourceItem = try await resolveMapItem(for: source)
        let destinationItem = try await resolveMapItem(for: destination)

        let directionsRequest = MKDirections.Request()
        directionsRequest.source = sourceItem
        directionsRequest.destination = destinationItem
        directionsRequest.transportType = .automobile
        directionsRequest.requestsAlternateRoutes = true

        let response = try await MKDirections(request: directionsRequest).calculate()
        guard !response.routes.isEmpty else {
            throw RouteLookupError.noRoute
        }

        return response.routes
            .sorted {
                if $0.expectedTravelTime == $1.expectedTravelTime {
                    return $0.distance < $1.distance
                }
                return $0.expectedTravelTime < $1.expectedTravelTime
            }
            .map { route in
                RouteEstimate(
                    id: UUID(),
                    sourceQuery: source.signature,
                    destinationQuery: destination.signature,
                    sourceName: resolvedDisplayName(for: source, item: sourceItem),
                    destinationName: resolvedDisplayName(for: destination, item: destinationItem),
                    destinationTimeZoneIdentifier: destinationItem.placemark.timeZone?.identifier,
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
                    maneuverSteps: RouteGeometry.maneuverSteps(from: route),
                    advisories: route.advisoryNotices
                )
            }
    }

    private static func resolveMapItem(for endpoint: RouteLookupEndpoint) async throws -> MKMapItem {
        if let coordinate = endpoint.coordinate {
            let placemark = MKPlacemark(coordinate: coordinate.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = endpoint.displayName
            return item
        }

        let trimmedQuery = endpoint.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            if endpoint.isCurrentLocation {
                throw RouteLookupError.currentLocationUnavailable
            }

            throw RouteLookupError.noResults(endpoint.displayName)
        }

        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = trimmedQuery
        let response = try await MKLocalSearch(request: searchRequest).start()

        guard let item = response.mapItems.first else {
            throw RouteLookupError.noResults(trimmedQuery)
        }

        return item
    }

    private static func resolvedDisplayName(for endpoint: RouteLookupEndpoint, item: MKMapItem) -> String {
        if let trimmed = endpoint.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return trimmed
        }

        return RouteFormatter.displayName(for: item, fallback: endpoint.query)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
