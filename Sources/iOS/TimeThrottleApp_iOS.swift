#if os(iOS)
import SwiftUI

@main
struct TimeThrottleIOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSRouteComparisonScreen()
        }
    }
}
#endif
