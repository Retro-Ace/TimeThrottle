#if os(iOS)
import SwiftUI
import UIKit
#if canImport(TimeThrottleSharedUI)
import TimeThrottleSharedUI
#endif

struct IOSRouteComparisonScreen: View {
    var body: some View {
        RouteComparisonView(
            configuration: RouteComparisonConfiguration(),
            brandLogo: brandLogoImage
        ) { routes, selectedRouteID in
            RoutePreviewMapView(routes: routes, selectedRouteID: selectedRouteID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var brandLogoImage: Image? {
        if let url = Bundle.main.url(forResource: "TimeThrottle", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }

        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "TimeThrottle", withExtension: "png", subdirectory: "TimeThrottleLogo"),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }
        #endif

        return nil
    }
}
#endif
