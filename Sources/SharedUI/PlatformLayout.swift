import SwiftUI

struct PlatformLayout<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        content
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        #endif
    }
}
