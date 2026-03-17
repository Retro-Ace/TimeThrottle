#if os(iOS)
@preconcurrency import MapKit
import SwiftUI
import UIKit
#if canImport(TimeThrottleSharedUI)
import TimeThrottleSharedUI
#endif

struct RoutePreviewMapView: UIViewRepresentable {
    let routes: [RouteEstimate]
    let selectedRouteID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(mapView: mapView, routes: routes, selectedRouteID: selectedRouteID)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lastRouteSignature = ""
        private var selectedRouteID: UUID?

        func update(mapView: MKMapView, routes: [RouteEstimate], selectedRouteID: UUID?) {
            let signature = routes.map { route in
                [
                    route.id.uuidString,
                    route.sourceQuery,
                    route.destinationQuery,
                    route.routeName,
                    String(route.routeCoordinates.count),
                    String(route.distanceMiles)
                ].joined(separator: "|")
            }
            .joined(separator: "||") + "::" + (selectedRouteID?.uuidString ?? "none")

            guard signature != lastRouteSignature else { return }
            lastRouteSignature = signature
            self.selectedRouteID = selectedRouteID

            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations)

            guard let selectedRoute = routes.first(where: { $0.id == selectedRouteID }) ?? routes.first else {
                return
            }

            let startAnnotation = MKPointAnnotation()
            startAnnotation.coordinate = selectedRoute.sourceCoordinate.coordinate
            startAnnotation.title = "Start"
            startAnnotation.subtitle = selectedRoute.sourceName

            let finishAnnotation = MKPointAnnotation()
            finishAnnotation.coordinate = selectedRoute.destinationCoordinate.coordinate
            finishAnnotation.title = "Finish"
            finishAnnotation.subtitle = selectedRoute.destinationName

            mapView.addAnnotations([startAnnotation, finishAnnotation])

            let orderedRoutes = routes.sorted { lhs, rhs in
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

            if let firstOverlay = mapView.overlays.first {
                var visibleMapRect = firstOverlay.boundingMapRect
                for overlay in mapView.overlays.dropFirst() {
                    visibleMapRect = visibleMapRect.union(overlay.boundingMapRect)
                }

                mapView.setVisibleMapRect(
                    visibleMapRect,
                    edgePadding: UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
                    animated: false
                )
            } else {
                let points = [selectedRoute.sourceCoordinate.coordinate, selectedRoute.destinationCoordinate.coordinate]
                let region = MKCoordinateRegion(points)
                mapView.setRegion(region, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            let isSelected = polyline.title == selectedRouteID?.uuidString
            renderer.strokeColor = isSelected ? UIColor.systemBlue : UIColor.systemBlue.withAlphaComponent(0.28)
            renderer.lineWidth = isSelected ? 6 : 4
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "RouteMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.canShowCallout = true

            if annotation.title == "Start" {
                view.markerTintColor = .systemGreen
                view.glyphImage = UIImage(systemName: "play.fill")
            } else {
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "flag.fill")
            }

            return view
        }
    }
}
#endif
