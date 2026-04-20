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
            brandLogo: brandLogoImage,
            resultBrandLogo: resultBrandLogoImage
        ) { routes, selectedRouteID in
            RoutePreviewMapView(routes: routes, selectedRouteID: selectedRouteID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var brandLogoImage: Image? {
        bundledImage(named: "TimeThrottle-Logo")
    }

    private var resultBrandLogoImage: Image? {
        bundledImage(named: "TimeThrottle-Logo-Only")
    }

    private func bundledImage(named resourceName: String) -> Image? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png", subdirectory: "TimeThrottleLogo")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }

        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "png", subdirectory: "TimeThrottleLogo")
            ?? Bundle.module.url(forResource: resourceName, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }
        #endif

        return nil
    }
}
#endif
