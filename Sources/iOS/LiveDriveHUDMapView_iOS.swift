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
    var mapMode: LiveDriveMapMode = .standard

    @State private var isFollowingUser = true
    @State private var recenterToken = UUID()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LiveDriveHUDTrackingMap(
                routes: routes,
                selectedRouteID: selectedRouteID,
                aircraft: aircraft,
                enforcementAlerts: enforcementAlerts,
                mapMode: mapMode,
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
    let mapMode: LiveDriveMapMode
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
        mapView.isRotateEnabled = false
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
        mapView.userTrackingMode = .follow
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
        private var lastAircraftSignature = ""
        private var lastEnforcementAlertSignature = ""
        private var lastRecenterToken: UUID?
        private var hasAppliedInitialFollowRegion = false
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

            if signature != lastRouteSignature {
                lastRouteSignature = signature
                syncRouteContext(on: mapView)
                if !hasResolvedUserCoordinate(on: mapView) {
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
                    String($0.lastPositionDate?.timeIntervalSince1970 ?? 0),
                    String($0.isStale)
                ].joined(separator: ":")
            }.joined(separator: "|")
            if aircraftSignature != lastAircraftSignature {
                lastAircraftSignature = aircraftSignature
                syncAircraft(on: mapView)
            }

            let enforcementAlertSignature = parent.enforcementAlerts.map {
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
                syncEnforcementAlerts(on: mapView)
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

        private func syncRouteContext(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
            let nonUserAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(nonUserAnnotations)

            guard let selectedRoute = selectedRoute(from: parent.routes, selectedRouteID: parent.selectedRouteID) else {
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
            syncEnforcementAlerts(on: mapView)
        }

        private func syncAircraft(on mapView: MKMapView) {
            let aircraftAnnotations = mapView.annotations.compactMap { $0 as? AircraftMapAnnotation }
            mapView.removeAnnotations(aircraftAnnotations)

            let annotations = parent.aircraft
                .filter { !$0.isStale && Self.isValidCoordinate($0.coordinate) }
                .map { aircraft in
                    AircraftMapAnnotation(aircraft: aircraft)
                }
            let visibleCount = Self.visibleAnnotationCount(annotations, on: mapView)
            mapView.addAnnotations(annotations)
            Self.logMarkerCounts(
                layer: "aircraft",
                passed: parent.aircraft.count,
                annotations: annotations.count,
                visible: visibleCount
            )
        }

        private func syncEnforcementAlerts(on mapView: MKMapView) {
            let alertAnnotations = mapView.annotations.compactMap { $0 as? EnforcementAlertMapAnnotation }
            mapView.removeAnnotations(alertAnnotations)

            let annotations = parent.enforcementAlerts
                .filter { !$0.isStale && Self.isValidCoordinate($0.coordinate) }
                .map { alert in
                    EnforcementAlertMapAnnotation(alert: alert)
                }
            let visibleCount = Self.visibleAnnotationCount(annotations, on: mapView)
            mapView.addAnnotations(annotations)
            Self.logMarkerCounts(
                layer: "enforcement",
                passed: parent.enforcementAlerts.count,
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
            if parent.isFollowingUser {
                if let coordinate = resolvedUserCoordinate(on: mapView) {
                    if forceRecenter || !hasAppliedInitialFollowRegion {
                        applyDrivingRegion(on: mapView, coordinate: coordinate, animated: forceRecenter)
                    }

                    if mapView.userTrackingMode != .follow {
                        mapView.setUserTrackingMode(.follow, animated: forceRecenter)
                    }
                } else if forceRecenter {
                    fitRouteContext(on: mapView)
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
        }

        private func fitRouteContext(on mapView: MKMapView) {
            guard let firstOverlay = mapView.overlays.first else { return }

            var visibleMapRect = firstOverlay.boundingMapRect
            for overlay in mapView.overlays.dropFirst() {
                visibleMapRect = visibleMapRect.union(overlay.boundingMapRect)
            }

            mapView.setVisibleMapRect(
                visibleMapRect,
                edgePadding: UIEdgeInsets(top: 28, left: 24, bottom: 28, right: 24),
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
            guard parent.isFollowingUser, let coordinate = userLocation.location?.coordinate else { return }
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }

            if !hasAppliedInitialFollowRegion {
                applyDrivingRegion(on: mapView, coordinate: coordinate, animated: false)
            }

            if mapView.userTrackingMode != .follow {
                mapView.setUserTrackingMode(.follow, animated: false)
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

    private let backgroundView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
    private let imageView = UIImageView(image: UIImage(systemName: "airplane"))

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        centerOffset = CGPoint(x: 0, y: -15)
        canShowCallout = true
        isEnabled = true
        isHidden = false
        alpha = 1
        displayPriority = .required
        zPriority = .max
        selectedZPriority = .max
        collisionMode = .none
        layer.zPosition = 1_000

        backgroundView.isUserInteractionEnabled = false
        backgroundView.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.88)
        backgroundView.layer.cornerRadius = 15
        backgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
        backgroundView.layer.borderWidth = 1
        backgroundView.layer.shadowColor = UIColor.black.cgColor
        backgroundView.layer.shadowOpacity = 0.22
        backgroundView.layer.shadowRadius = 6
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(backgroundView)

        imageView.isUserInteractionEnabled = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(x: 7, y: 7, width: 16, height: 16)
        backgroundView.addSubview(imageView)
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
        collisionMode = .none
        layer.zPosition = 1_000
        if let heading = annotation.aircraft.headingDegrees {
            imageView.transform = CGAffineTransform(rotationAngle: heading * .pi / 180)
        } else {
            imageView.transform = .identity
        }
    }
}

private final class AircraftMapAnnotation: NSObject, MKAnnotation {
    let aircraft: Aircraft
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(aircraft: Aircraft) {
        self.aircraft = aircraft
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
