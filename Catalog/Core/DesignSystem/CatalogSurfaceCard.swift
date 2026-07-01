import SwiftUI

struct CatalogSurfaceCard<Content: View>: View {
    private let content: Content

    private enum Metrics {
        static let cornerRadius: CGFloat = CatalogCornerRadii.section
        static let padding: CGFloat = 16
        static let strokeWidth: CGFloat = 1
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Metrics.padding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: Metrics.strokeWidth)
            }
    }
}
