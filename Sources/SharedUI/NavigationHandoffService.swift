import Foundation
#if os(iOS)
import UIKit
#endif

public enum NavigationHandoffOutcome: Equatable, Sendable {
    case opened(provider: NavigationProvider)
    case openedWithFallback(provider: NavigationProvider)
    case unavailable(provider: NavigationProvider)

    public var userFacingMessage: String? {
        switch self {
        case .opened:
            return nil
        case .openedWithFallback(let provider):
            switch provider {
            case .googleMaps:
                return "Google Maps is not installed. Opening the web route instead."
            case .waze:
                return "Waze is not installed. Opening the web route instead."
            case .appleMaps, .askEveryTime:
                return nil
            }
        case .unavailable(let provider):
            switch provider {
            case .googleMaps:
                return "Could not open Google Maps. Live Drive tracking is still running."
            case .waze:
                return "Could not open Waze. Live Drive tracking is still running."
            case .appleMaps:
                return "Could not open Apple Maps. Live Drive tracking is still running."
            case .askEveryTime:
                return nil
            }
        }
    }
}

public enum NavigationHandoffService {
    @MainActor
    public static func handoff(
        provider: NavigationProvider,
        route: RouteEstimate
    ) async -> NavigationHandoffOutcome {
        switch provider {
        case .appleMaps:
            guard let url = appleMapsDirectionsURL(for: route) else {
                return .unavailable(provider: provider)
            }

            return await open(url: url)
                ? .opened(provider: provider)
                : .unavailable(provider: provider)

        case .googleMaps:
            if canOpenGoogleMaps(),
               let appURL = googleMapsAppURL(for: route),
               await open(url: appURL) {
                return .opened(provider: provider)
            }

            guard let fallbackURL = googleMapsWebURL(for: route) else {
                return .unavailable(provider: provider)
            }

            return await open(url: fallbackURL)
                ? .openedWithFallback(provider: provider)
                : .unavailable(provider: provider)

        case .waze:
            if canOpenWaze(),
               let appURL = wazeAppURL(for: route),
               await open(url: appURL) {
                return .opened(provider: provider)
            }

            guard let fallbackURL = wazeWebURL(for: route) else {
                return .unavailable(provider: provider)
            }

            return await open(url: fallbackURL)
                ? .openedWithFallback(provider: provider)
                : .unavailable(provider: provider)

        case .askEveryTime:
            return .unavailable(provider: provider)
        }
    }

    @MainActor
    private static func canOpenGoogleMaps() -> Bool {
#if os(iOS)
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
#else
        return false
#endif
    }

    @MainActor
    private static func canOpenWaze() -> Bool {
#if os(iOS)
        guard let url = URL(string: "waze://") else { return false }
        return UIApplication.shared.canOpenURL(url)
#else
        return false
#endif
    }

    @MainActor
    private static func open(url: URL) async -> Bool {
#if os(iOS)
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
#else
        return false
#endif
    }

    private static func appleMapsDirectionsURL(for route: RouteEstimate) -> URL? {
        guard var components = URLComponents(string: "maps://") else { return nil }

        var queryItems = [
            URLQueryItem(name: "daddr", value: coordinateString(route.destinationCoordinate)),
            URLQueryItem(name: "dirflg", value: "d")
        ]

        if !route.sourceQuery.hasPrefix("current:") {
            queryItems.insert(URLQueryItem(name: "saddr", value: coordinateString(route.sourceCoordinate)), at: 0)
        }

        components.queryItems = queryItems
        return components.url
    }

    private static func googleMapsAppURL(for route: RouteEstimate) -> URL? {
        guard var components = URLComponents(string: "comgooglemaps://") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "saddr", value: coordinateString(route.sourceCoordinate)),
            URLQueryItem(name: "daddr", value: coordinateString(route.destinationCoordinate)),
            URLQueryItem(name: "directionsmode", value: "driving")
        ]
        return components.url
    }

    private static func googleMapsWebURL(for route: RouteEstimate) -> URL? {
        guard var components = URLComponents(string: "https://www.google.com/maps/dir/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: coordinateString(route.sourceCoordinate)),
            URLQueryItem(name: "destination", value: coordinateString(route.destinationCoordinate)),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        return components.url
    }

    private static func wazeAppURL(for route: RouteEstimate) -> URL? {
        guard var components = URLComponents(string: "waze://") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "ll", value: coordinateString(route.destinationCoordinate)),
            URLQueryItem(name: "navigate", value: "yes")
        ]
        return components.url
    }

    private static func wazeWebURL(for route: RouteEstimate) -> URL? {
        guard var components = URLComponents(string: "https://waze.com/ul") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "ll", value: coordinateString(route.destinationCoordinate)),
            URLQueryItem(name: "navigate", value: "yes")
        ]
        return components.url
    }

    private static func coordinateString(_ coordinate: RouteCoordinate) -> String {
        "\(coordinate.latitude),\(coordinate.longitude)"
    }
}
