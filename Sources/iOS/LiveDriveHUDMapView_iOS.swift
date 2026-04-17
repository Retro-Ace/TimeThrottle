#if os(iOS)
@preconcurrency import MapKit
import SwiftUI
import UIKit
#if canImport(TimeThrottleSharedUI)
import TimeThrottleSharedUI
#endif

struct LiveDriveHUDMapView: View {
    let routes: [RouteEstimate]
    let selectedRouteID: UUID?

    @State private var isFollowingUser = true
    @State private var recenterToken = UUID()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LiveDriveHUDTrackingMap(
                routes: routes,
                selectedRouteID: selectedRouteID,
                isFollowingUser: $isFollowingUser,
                recenterToken: recenterToken
            )

            if !isFollowingUser {
                Button {
                    recenterToken = UUID()
                    isFollowingUser = true
                } label: {
                    Label("Recenter", systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Palette.ink.opacity(0.86), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, recenterHorizontalPadding)
                .padding(.bottom, recenterBottomPadding)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recenterBottomPadding: CGFloat {
        max(activeWindowSafeAreaInsets.bottom, 16) + 32
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
        private var lastRecenterToken: UUID?
        private var hasAppliedInitialFollowRegion = false
        private var userInitiatedMapChange = false

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
            let signature = routeSignature(routes: parent.routes, selectedRouteID: parent.selectedRouteID)

            if signature != lastRouteSignature {
                lastRouteSignature = signature
                syncRouteContext(on: mapView)
                if !hasResolvedUserCoordinate(on: mapView) {
                    fitRouteContext(on: mapView)
                }
            }

            let shouldRecenter = lastRecenterToken != parent.recenterToken
            if shouldRecenter {
                lastRecenterToken = parent.recenterToken
            }

            syncFollowState(on: mapView, forceRecenter: shouldRecenter)
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
#endif
