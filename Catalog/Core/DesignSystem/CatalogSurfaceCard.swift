import SwiftUI

private enum CatalogSurfaceCardMetrics {
    static let strokeWidth: CGFloat = 1
}

extension View {
    func catalogSurfaceCard() -> some View {
        self
            .padding(CatalogMetrics.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.section, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.section, style: .continuous)
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceCardMetrics.strokeWidth)
            }
    }
}
