import SwiftUI

private enum CatalogSurfaceCardMetrics {
    static let cornerRadius: CGFloat = CatalogCornerRadii.section
    static let padding: CGFloat = 16
    static let strokeWidth: CGFloat = 1
}

extension View {
    func catalogSurfaceCard() -> some View {
        self
            .padding(CatalogSurfaceCardMetrics.padding)
            .background(
                RoundedRectangle(cornerRadius: CatalogSurfaceCardMetrics.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatalogSurfaceCardMetrics.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: CatalogSurfaceCardMetrics.strokeWidth)
            }
    }
}
