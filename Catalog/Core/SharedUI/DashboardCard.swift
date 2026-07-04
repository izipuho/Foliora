import SwiftUI

struct DashboardCard<Leading: View, Content: View>: View {
    let leading: Leading
    let content: Content

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.md) {
            leading

            content
        }
        .catalogSurfaceCard()
    }
}
