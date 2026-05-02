#if os(iOS)
@preconcurrency import MapKit
import SwiftUI
import UIKit
#if canImport(OSLog)
import OSLog
#endif
#if canImport(TimeThrottleSharedUI)
import TimeThrottleSharedUI
#endif

struct LiveDriveHUDMapView: View {
    let routes: [RouteEstimate]
    let selectedRouteID: UUID?
    var aircraft: [Aircraft] = []
    var enforcementAlerts: [EnforcementAlert] = []
    var weatherCheckpoints: [RouteWeatherMapCheckpoint] = []
    var mapMode: LiveDriveMapMode = .standard
    var prefersRouteOverview = false
    var routeEdgePadding = UIEdgeInsets(top: 28, left: 24, bottom: 28, right: 24)

    @State private var isFollowingUser = true
    @State private var recenterToken = UUID()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LiveDriveHUDTrackingMap(
                routes: routes,
                selectedRouteID: selectedRouteID,
                aircraft: aircraft,
                enforcementAlerts: enforcementAlerts,
                weatherCheckpoints: weatherCheckpoints,
                mapMode: mapMode,
                prefersRouteOverview: prefersRouteOverview,
                routeEdgePadding: routeEdgePadding,
                isFollowingUser: $isFollowingUser,
                recenterToken: recenterToken
            )

            Button {
                recenterToken = UUID()
                isFollowingUser = true
            } label: {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .background(Palette.ink.opacity(0.74), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(isFollowingUser ? 0.14 : 0.24), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recenter map")
            .padding(.trailing, recenterHorizontalPadding)
            .padding(.bottom, recenterBottomPadding)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recenterBottomPadding: CGFloat {
        max(activeWindowSafeAreaInsets.bottom, 16) + 218
    }

    private var recenterHorizontalPadding: CGFloat {
        max(activeWindowSafeAreaInsets.right, 0) + 22
    }

    private var activeWindowSafeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let keyWindow = activeScene?.windows.first(where: \.isKeyWindow)
        return keyWindow?.safeAreaInsets ?? .zero
    }
}

private struct LiveDriveHUDTrackingMap: UIViewRepresentable {
    let routes: [RouteEstimate]
    let selectedRouteID: UUID?
    let aircraft: [Aircraft]
    let enforcementAlerts: [EnforcementAlert]
    let weatherCheckpoints: [RouteWeatherMapCheckpoint]
    let mapMode: LiveDriveMapMode
    let prefersRouteOverview: Bool
    let routeEdgePadding: UIEdgeInsets
    @Binding var isFollowingUser: Bool
    let recenterToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(
            AircraftAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: AircraftAnnotationView.reuseIdentifier
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "HUDEnforcementAlertMarker"
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "HUDWeatherCheckpointMarker"
        )
        mapView.userTrackingMode = .followWithHeading
        let followPanRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleUserPan(_:))
        )
        followPanRecognizer.cancelsTouchesInView = false
        followPanRecognizer.delegate = context.coordinator
        mapView.addGestureRecognizer(followPanRecognizer)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(mapView: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: LiveDriveHUDTrackingMap

        private var lastRouteSignature = ""
        private var lastRouteEdgePaddingSignature = ""
        private var lastAircraftSignature = ""
        private var lastEnforcementAlertSignature = ""
        private var lastWeatherCheckpointSignature = ""
        private var lastRecenterToken: UUID?
        private var hasAppliedInitialFollowRegion = false
        private var hasAppliedFallbackRegion = false
        private var hasScheduledInitialLocationSnap = false
        private var userInitiatedMapChange = false

        #if canImport(OSLog)
        private static let logger = Logger(subsystem: "com.timethrottle.app", category: "HUDMapMarkers")
        #endif

        init(parent: LiveDriveHUDTrackingMap) {
            self.parent = parent
        }

        @objc
        func handleUserPan(_ recognizer: UIPanGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }

            switch recognizer.state {
            case .began, .changed:
                userInitiatedMapChange = true

                if mapView.userTrackingMode != .none {
                    mapView.setUserTrackingMode(.none, animated: false)
                }

                if parent.isFollowingUser {
                    parent.isFollowingUser = false
                }
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func update(mapView: MKMapView) {
            let desiredMapType = mapType(for: parent.mapMode)
            if mapView.mapType != desiredMapType {
                mapView.mapType = desiredMapType
            }

            let signature = routeSignature(routes: parent.routes, selectedRouteID: parent.selectedRouteID)
            let edgePaddingSignature = routeEdgePaddingSignature(parent.routeEdgePadding)

            if signature != lastRouteSignature {
                lastRouteSignature = signature
                syncRouteContext(on: mapView)
                if parent.prefersRouteOverview || !hasResolvedUserCoordinate(on: mapView) {
                    fitRouteContext(on: mapView)
                }
            }

            if edgePaddingSignature != lastRouteEdgePaddingSignature {
                lastRouteEdgePaddingSignature = edgePaddingSignature
                if !parent.routes.isEmpty {
                    fitRouteContext(on: mapView)
                }
            }

            let aircraftSignature = parent.aircraft.map {
                [
                    $0.id,
                    String($0.coordinate.latitude),
                    String($0.coordinate.longitude),
                    String($0.altitudeFeet ?? -1),
                    String($0.groundSpeedMPH ?? -1),
                    String($0.headingDegrees ?? -1),
                    String($0.distanceMiles ?? -1),
                    String($0.isLowNearbyAircraft),
                    String($0.lastPositionDate?.timeIntervalSince1970 ?? 0),
                    String($0.isStale)
                ].joined(separator: ":")
            }.joined(separator: "|")
            if aircraftSignature != lastAircraftSignature {
                lastAircraftSignature = aircraftSignature
                syncAircraft(on: mapView)
            }

            let renderedEnforcementAlerts = Array(
                parent.enforcementAlerts.prefix(EnforcementAlertVisibilityPolicy.routeActiveVisibleLimit)
            )
            let enforcementAlertSignature = renderedEnforcementAlerts.map {
                [
                    $0.id,
                    String($0.coordinate.latitude),
                    String($0.coordinate.longitude),
                    String($0.distanceMiles ?? -1),
                    String($0.lastUpdated?.timeIntervalSince1970 ?? 0),
                    String($0.isStale)
                ].joined(separator: ":")
            }.joined(separator: "|")
            if enforcementAlertSignature != lastEnforcementAlertSignature {
                lastEnforcementAlertSignature = enforcementAlertSignature
                syncEnforcementAlerts(on: mapView, alerts: renderedEnforcementAlerts)
            }

            let weatherCheckpointSignature = parent.weatherCheckpoints.map {
                [
                    $0.id.uuidString,
                    String($0.coordinate.latitude),
                    String($0.coordinate.longitude),
                    $0.title,
                    $0.arrivalText,
                    $0.forecastText,
                    $0.temperatureText ?? "",
                    $0.systemImage
                ].joined(separator: ":")
            }.joined(separator: "|")
            if weatherCheckpointSignature != lastWeatherCheckpointSignature {
                lastWeatherCheckpointSignature = weatherCheckpointSignature
                syncWeatherCheckpoints(on: mapView)
            }

            let shouldRecenter = lastRecenterToken != parent.recenterToken
            if shouldRecenter {
                lastRecenterToken = parent.recenterToken
            }

            syncFollowState(on: mapView, forceRecenter: shouldRecenter)
        }

        private func mapType(for mode: LiveDriveMapMode) -> MKMapType {
            switch mode {
            case .standard:
                return .mutedStandard
            case .satellite:
                return .satellite
            }
        }

        private func routeSignature(routes: [RouteEstimate], selectedRouteID: UUID?) -> String {
            routes.map { route in
                [
                    route.id.uuidString,
                    route.routeName,
                    route.sourceName,
                    route.destinationName,
                    String(route.routeCoordinates.count),
                    String(route.distanceMiles)
                ].joined(separator: "|")
            }
            .joined(separator: "||") + "::" + (selectedRouteID?.uuidString ?? "none")
        }

        private func routeEdgePaddingSignature(_ padding: UIEdgeInsets) -> String {
            [
                padding.top,
                padding.left,
                padding.bottom,
                padding.right
            ]
            .map { String(format: "%.1f", $0) }
            .joined(separator: ":")
        }

        private func syncRouteContext(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
            let nonUserAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(nonUserAnnotations)

            guard let selectedRoute = selectedRoute(from: parent.routes, selectedRouteID: parent.selectedRouteID) else {
                syncAircraft(on: mapView)
                syncEnforcementAlerts(
                    on: mapView,
                    alerts: Array(parent.enforcementAlerts.prefix(EnforcementAlertVisibilityPolicy.routeActiveVisibleLimit))
                )
                syncWeatherCheckpoints(on: mapView)
                return
            }

            let orderedRoutes = parent.routes.sorted { lhs, rhs in
                if lhs.id == selectedRoute.id { return false }
                if rhs.id == selectedRoute.id { return true }
                return lhs.expectedTravelMinutes < rhs.expectedTravelMinutes
            }

            for route in orderedRoutes {
                let coordinates = route.routeCoordinates.map(\.coordinate)
                guard coordinates.count >= 2 else { continue }
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                polyline.title = route.id.uuidString
                mapView.addOverlay(polyline)
            }

            let destinationAnnotation = MKPointAnnotation()
            destinationAnnotation.coordinate = selectedRoute.destinationCoordinate.coordinate
            destinationAnnotation.title = "Destination"
            destinationAnnotation.subtitle = selectedRoute.destinationName
            mapView.addAnnotation(destinationAnnotation)

            syncAircraft(on: mapView)
            syncEnforcementAlerts(
                on: mapView,
                alerts: Array(parent.enforcementAlerts.prefix(EnforcementAlertVisibilityPolicy.routeActiveVisibleLimit))
            )
            syncWeatherCheckpoints(on: mapView)
        }

        private func syncAircraft(on mapView: MKMapView) {
            let existingAircraftAnnotations = mapView.annotations.compactMap { $0 as? AircraftMapAnnotation }
            mapView.removeAnnotations(existingAircraftAnnotations)

            let annotations = parent.aircraft
                .filter { !$0.isStale && Self.isValidCoordinate($0.coordinate) }
            let nearestLowAircraftID = annotations
                .filter { $0.isLowNearbyAircraft }
                .sorted {
                    ($0.distanceMiles ?? .greatestFiniteMagnitude) < ($1.distanceMiles ?? .greatestFiniteMagnitude)
                }
                .first?
                .id

            let aircraftAnnotations = annotations
                .map { aircraft in
                    AircraftMapAnnotation(
                        aircraft: aircraft,
                        isNearestLowAircraft: aircraft.id == nearestLowAircraftID
                    )
                }
            let visibleCount = Self.visibleAnnotationCount(aircraftAnnotations, on: mapView)
            mapView.addAnnotations(aircraftAnnotations)
            Self.logMarkerCounts(
                layer: "aircraft",
                passed: parent.aircraft.count,
                annotations: aircraftAnnotations.count,
                visible: visibleCount
            )
        }

        private func syncEnforcementAlerts(on mapView: MKMapView, alerts: [EnforcementAlert]) {
            let alertAnnotations = mapView.annotations.compactMap { $0 as? EnforcementAlertMapAnnotation }
            mapView.removeAnnotations(alertAnnotations)

            let annotations = alerts
                .filter { !$0.isStale && Self.isValidCoordinate($0.coordinate) }
                .map { alert in
                    EnforcementAlertMapAnnotation(alert: alert)
                }
            let visibleCount = Self.visibleAnnotationCount(annotations, on: mapView)
            mapView.addAnnotations(annotations)
            Self.logMarkerCounts(
                layer: "enforcement",
                passed: alerts.count,
                annotations: annotations.count,
                visible: visibleCount
            )
        }

        private func syncWeatherCheckpoints(on mapView: MKMapView) {
            let weatherAnnotations = mapView.annotations.compactMap { $0 as? WeatherCheckpointMapAnnotation }
            mapView.removeAnnotations(weatherAnnotations)

            guard selectedRoute(from: parent.routes, selectedRouteID: parent.selectedRouteID) != nil else { return }

            let annotations = parent.weatherCheckpoints
                .filter { Self.isValidCoordinate($0.coordinate) }
                .map { checkpoint in
                    WeatherCheckpointMapAnnotation(checkpoint: checkpoint)
                }
            let visibleCount = Self.visibleAnnotationCount(annotations, on: mapView)
            mapView.addAnnotations(annotations)
            Self.logMarkerCounts(
                layer: "weather",
                passed: parent.weatherCheckpoints.count,
                annotations: annotations.count,
                visible: visibleCount
            )
        }

        private static func isValidCoordinate(_ coordinate: GuidanceCoordinate) -> Bool {
            CLLocationCoordinate2DIsValid(coordinate.clLocationCoordinate)
        }

        private static func visibleAnnotationCount<Annotation: MKAnnotation>(
            _ annotations: [Annotation],
            on mapView: MKMapView
        ) -> Int {
            annotations.filter { annotation in
                mapView.visibleMapRect.contains(MKMapPoint(annotation.coordinate))
            }.count
        }

        private static func logMarkerCounts(
            layer: String,
            passed: Int,
            annotations: Int,
            visible: Int
        ) {
            #if canImport(OSLog)
            logger.debug(
                "HUD map \(layer, privacy: .public) markers passed=\(passed, privacy: .public) annotations=\(annotations, privacy: .public) visible=\(visible, privacy: .public)"
            )
            #endif
        }

        private func syncFollowState(on mapView: MKMapView, forceRecenter: Bool) {
            if parent.prefersRouteOverview && parent.isFollowingUser && !parent.routes.isEmpty {
                if mapView.userTrackingMode != .none {
                    mapView.setUserTrackingMode(.none, animated: false)
                }
                fitRouteContext(on: mapView)
                hasAppliedInitialFollowRegion = true
                return
            }

            if parent.isFollowingUser {
                if let coordinate = resolvedUserCoordinate(on: mapView) {
                    if forceRecenter || !hasAppliedInitialFollowRegion {
                        applyDrivingRegion(on: mapView, coordinate: coordinate, animated: forceRecenter)
                    }

                    if mapView.userTrackingMode != .followWithHeading {
                        mapView.setUserTrackingMode(.followWithHeading, animated: forceRecenter)
                    }
                } else if forceRecenter {
                    fitRouteContext(on: mapView)
                } else if parent.routes.isEmpty && !hasAppliedInitialFollowRegion {
                    scheduleInitialLocationSnapIfNeeded(on: mapView)
                    if !hasAppliedFallbackRegion {
                        applyFallbackRegion(on: mapView)
                    }
                }
            } else if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: false)
            }
        }

        private func applyDrivingRegion(
            on mapView: MKMapView,
            coordinate: CLLocationCoordinate2D,
            animated: Bool
        ) {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1_800,
                longitudinalMeters: 1_800
            )
            mapView.setRegion(region, animated: animated)
            hasAppliedInitialFollowRegion = true
            hasAppliedFallbackRegion = false
        }

        private func applyFallbackRegion(on mapView: MKMapView) {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
                latitudinalMeters: 4_500_000,
                longitudinalMeters: 4_500_000
            )
            mapView.setRegion(region, animated: false)
            hasAppliedFallbackRegion = true
        }

        private func scheduleInitialLocationSnapIfNeeded(on mapView: MKMapView) {
            guard !hasScheduledInitialLocationSnap else { return }
            hasScheduledInitialLocationSnap = true

            [0.15, 0.45, 0.9, 1.6].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    guard !self.hasAppliedInitialFollowRegion, !self.userInitiatedMapChange else { return }
                    guard let coordinate = self.resolvedUserCoordinate(on: mapView) else { return }

                    self.parent.isFollowingUser = true
                    self.applyDrivingRegion(on: mapView, coordinate: coordinate, animated: delay > 0.15)
                    if mapView.userTrackingMode != .followWithHeading {
                        mapView.setUserTrackingMode(.followWithHeading, animated: delay > 0.15)
                    }
                }
            }
        }

        private func fitRouteContext(on mapView: MKMapView) {
            guard let firstOverlay = mapView.overlays.first else { return }

            var visibleMapRect = firstOverlay.boundingMapRect
            for overlay in mapView.overlays.dropFirst() {
                visibleMapRect = visibleMapRect.union(overlay.boundingMapRect)
            }

            mapView.setVisibleMapRect(
                visibleMapRect,
                edgePadding: parent.routeEdgePadding,
                animated: false
            )
        }

        private func selectedRoute(from routes: [RouteEstimate], selectedRouteID: UUID?) -> RouteEstimate? {
            routes.first(where: { $0.id == selectedRouteID }) ?? routes.first
        }

        private func hasResolvedUserCoordinate(on mapView: MKMapView) -> Bool {
            resolvedUserCoordinate(on: mapView) != nil
        }

        private func resolvedUserCoordinate(on mapView: MKMapView) -> CLLocationCoordinate2D? {
            guard let location = mapView.userLocation.location else { return nil }
            let coordinate = location.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            return coordinate
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            let isSelected = polyline.title == parent.selectedRouteID?.uuidString
            renderer.strokeColor = isSelected ? UIColor.systemBlue : UIColor.systemBlue.withAlphaComponent(0.18)
            renderer.lineWidth = isSelected ? 5 : 3
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            if let aircraftAnnotation = annotation as? AircraftMapAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: AircraftAnnotationView.reuseIdentifier
                ) as? AircraftAnnotationView
                    ?? AircraftAnnotationView(annotation: annotation, reuseIdentifier: AircraftAnnotationView.reuseIdentifier)

                view.annotation = aircraftAnnotation
                view.configure(with: aircraftAnnotation)
                return view
            }

            if let alertAnnotation = annotation as? EnforcementAlertMapAnnotation {
                let identifier = "HUDEnforcementAlertMarker"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = alertAnnotation
                view.canShowCallout = true
                view.isHidden = false
                view.alpha = 1
                view.displayPriority = .required
                view.zPriority = .max
                view.selectedZPriority = .max
                view.collisionMode = .none
                view.layer.zPosition = 990
                view.markerTintColor = alertAnnotation.markerColor
                view.glyphImage = UIImage(systemName: alertAnnotation.glyphName)
                return view
            }

            if let weatherAnnotation = annotation as? WeatherCheckpointMapAnnotation {
                let identifier = "HUDWeatherCheckpointMarker"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

                view.annotation = weatherAnnotation
                view.canShowCallout = true
                view.isHidden = false
                view.alpha = 0.96
                view.displayPriority = .defaultHigh
                view.zPriority = .defaultSelected
                view.selectedZPriority = .max
                view.collisionMode = .circle
                view.markerTintColor = .systemTeal
                view.glyphTintColor = .white
                view.glyphImage = UIImage(systemName: weatherAnnotation.glyphName)
                view.detailCalloutAccessoryView = WeatherCheckpointMapAnnotation.detailLabel(for: weatherAnnotation)
                return view
            }

            let identifier = "HUDRouteMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.canShowCallout = false
            view.markerTintColor = .systemRed
            view.glyphImage = UIImage(systemName: "flag.fill")
            return view
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard parent.isFollowingUser || (!userInitiatedMapChange && !hasAppliedInitialFollowRegion),
                  let coordinate = userLocation.location?.coordinate else { return }
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }

            if !hasAppliedInitialFollowRegion {
                parent.isFollowingUser = true
                applyDrivingRegion(on: mapView, coordinate: coordinate, animated: false)
            }

            if mapView.userTrackingMode != .followWithHeading {
                mapView.setUserTrackingMode(.followWithHeading, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if userInitiatedMapChange {
                return
            }

            userInitiatedMapChange = mapView.gestureRecognizers?.contains(where: {
                switch $0.state {
                case .began, .changed:
                    return true
                default:
                    return false
                }
            }) ?? false
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard userInitiatedMapChange else { return }
            userInitiatedMapChange = false

            if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: false)
            }

            parent.isFollowingUser = false
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            if mode == .none {
                parent.isFollowingUser = false
            } else {
                parent.isFollowingUser = true
            }
        }
    }
}

private final class WeatherCheckpointMapAnnotation: NSObject, MKAnnotation {
    let checkpoint: RouteWeatherMapCheckpoint
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(checkpoint: RouteWeatherMapCheckpoint) {
        self.checkpoint = checkpoint
        self.coordinate = checkpoint.coordinate.clLocationCoordinate
        self.title = checkpoint.title

        let detailParts = [
            checkpoint.arrivalText.isEmpty ? nil : checkpoint.arrivalText,
            checkpoint.temperatureText,
            checkpoint.forecastText.isEmpty ? nil : checkpoint.forecastText
        ].compactMap { $0 }
        self.subtitle = detailParts.joined(separator: " • ")
    }

    var glyphName: String {
        checkpoint.systemImage
    }

    static func detailLabel(for annotation: WeatherCheckpointMapAnnotation) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.text = [
            annotation.checkpoint.arrivalText.isEmpty ? nil : "Expected \(annotation.checkpoint.arrivalText)",
            annotation.checkpoint.temperatureText.map { "Temperature \($0)" },
            annotation.checkpoint.forecastText.isEmpty ? nil : annotation.checkpoint.forecastText
        ].compactMap { $0 }.joined(separator: "\n")
        return label
    }
}

private final class EnforcementAlertMapAnnotation: NSObject, MKAnnotation {
    let alert: EnforcementAlert
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(alert: EnforcementAlert) {
        self.alert = alert
        self.coordinate = alert.coordinate.clLocationCoordinate
        self.title = alert.title

        let detailParts = [
            alert.distanceMiles.map { "\(String(format: "%.1f", $0)) mi away" },
            alert.confidence.map { "Confidence \(Int(($0 * 100).rounded()))%" },
            alert.source.isEmpty ? nil : alert.source,
            alert.isStale ? "Stale" : nil
        ].compactMap { $0 }
        self.subtitle = detailParts.joined(separator: " • ")
    }

    var glyphName: String {
        switch alert.type {
        case .speedCamera:
            return "speedometer"
        case .redLightCamera:
            return "trafficlight"
        case .policeReported:
            return "camera.viewfinder"
        case .other:
            return "camera.viewfinder"
        }
    }

    var markerColor: UIColor {
        switch alert.type {
        case .speedCamera:
            return .systemOrange
        case .redLightCamera:
            return .systemRed
        case .policeReported:
            return .systemBlue
        case .other:
            return .systemGray
        }
    }
}

private final class AircraftAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "HUDAircraftMarker"

    private let ringView = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
    private let imageView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        centerOffset = .zero
        canShowCallout = true
        isEnabled = true
        isHidden = false
        alpha = 1
        displayPriority = .required
        zPriority = .max
        selectedZPriority = .max
        collisionMode = .circle
        layer.zPosition = 1_000

        ringView.isUserInteractionEnabled = false
        ringView.layer.cornerRadius = bounds.width / 2
        ringView.layer.borderWidth = 2
        ringView.layer.masksToBounds = true
        ringView.layer.shadowColor = UIColor.black.cgColor
        ringView.layer.shadowOpacity = 0.22
        ringView.layer.shadowRadius = 6
        ringView.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(ringView)

        imageView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.frame = bounds.insetBy(dx: 7, dy: 7)
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func configure(with annotation: AircraftMapAnnotation) {
        self.annotation = annotation
        isHidden = false
        alpha = 1
        displayPriority = .required
        zPriority = .max
        selectedZPriority = .max
        collisionMode = .circle
        layer.zPosition = 1_000

        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: annotation.isNearestLowAircraft ? 19 : 16,
            weight: .bold
        )
        imageView.image = UIImage(systemName: "airplane", withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        if let heading = annotation.aircraft.headingDegrees {
            imageView.transform = CGAffineTransform(rotationAngle: (heading - 90) * .pi / 180)
        } else {
            imageView.transform = .identity
        }

        ringView.backgroundColor = annotation.isNearestLowAircraft
            ? UIColor.systemPurple.withAlphaComponent(0.92)
            : UIColor.black.withAlphaComponent(0.72)
        ringView.layer.borderColor = annotation.isNearestLowAircraft
            ? UIColor.white.withAlphaComponent(0.88).cgColor
            : UIColor.systemPurple.withAlphaComponent(0.86).cgColor
        ringView.transform = annotation.isNearestLowAircraft
            ? CGAffineTransform(scaleX: 1.18, y: 1.18)
            : .identity
    }
}

private final class AircraftMapAnnotation: NSObject, MKAnnotation {
    let aircraft: Aircraft
    let isNearestLowAircraft: Bool
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(aircraft: Aircraft, isNearestLowAircraft: Bool) {
        self.aircraft = aircraft
        self.isNearestLowAircraft = isNearestLowAircraft
        self.coordinate = aircraft.coordinate.clLocationCoordinate
        self.title = aircraft.callsign

        let detailParts = [
            aircraft.altitudeFeet.map { "Alt \(Int($0.rounded())) ft" },
            aircraft.groundSpeedMPH.map { "Speed \(Int($0.rounded())) mph" },
            aircraft.headingDegrees.map { "Heading \(Int($0.rounded()))°" },
            aircraft.distanceMiles.map { "\(String(format: "%.1f", $0)) mi away" },
            aircraft.dataAgeSeconds.map { "Updated \(Self.ageString($0)) ago" }
        ].compactMap { $0 }
        self.subtitle = detailParts.joined(separator: " • ")
    }

    private static func ageString(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return value < 60 ? "\(value)s" : "\(value / 60)m"
    }
}
#endif
