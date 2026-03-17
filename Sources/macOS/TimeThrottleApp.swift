#if os(macOS)
import AppKit
import SwiftUI
#if canImport(TimeThrottleSharedUI)
import TimeThrottleSharedUI
#endif

@main
struct TimeThrottleApp: App {
    var body: some Scene {
        WindowGroup("TimeThrottle") {
            RouteComparisonView(
                platformStyle: .macOS,
                platformBadgeText: "macOS",
                brandLogo: brandLogoImage
            ) { routes, selectedRouteID in
                RoutePreviewMapView(routes: routes, selectedRouteID: selectedRouteID)
            }
                .frame(minWidth: 960, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
    }

    private var brandLogoImage: Image? {
        if let url = Bundle.main.url(forResource: "TimeThrottle", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }

        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "TimeThrottle", withExtension: "png", subdirectory: "TimeThrottleLogo"),
           let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        #endif

        return nil
    }
}
#endif
