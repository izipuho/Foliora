import SwiftUI

private enum CatalogSurfaceCardMetrics {
    static let strokeWidth: CGFloat = 1
}

extension View {
    func catalogSurfaceCard() -> some View {
        self
            .padding(CatalogMetrics.Spacing.lg)
            .background(
                CatalogShapes.section
                    .fill(.regularMaterial)
            )
            .overlay {
                CatalogShapes.section
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceCardMetrics.strokeWidth)
            }
    }
}
