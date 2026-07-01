import SwiftUI

struct CatalogSurfaceCapsule<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
