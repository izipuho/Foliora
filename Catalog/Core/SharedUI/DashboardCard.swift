import SwiftUI

struct DashboardCard<Leading: View, Content: View>: View {
    let leading: Leading
    let content: Content

    private enum Metrics {
        static var horizontalSpacing: CGFloat { 14 }
    }

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: Metrics.horizontalSpacing) {
            leading

            content
        }
        .catalogSurfaceCard()
    }
}
