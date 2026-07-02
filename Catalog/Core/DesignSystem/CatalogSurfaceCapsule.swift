import SwiftUI

struct CatalogSurfaceCapsule<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, CatalogMetrics.Spacing.md)
            .padding(.vertical, CatalogMetrics.Spacing.xs)
            .background {
                Capsule()
                    .fill(.thinMaterial)
            }
            .overlay {
                Capsule()
                    .stroke(CatalogSemanticColors.separator, lineWidth: 1)
            }
    }
}
