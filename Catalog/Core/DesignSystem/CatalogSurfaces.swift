import SwiftUI

extension View {
    func catalogSurfaceCapsule() -> some View {
        self
            .padding(.horizontal, CatalogMetrics.Spacing.md)
            .padding(.vertical, CatalogMetrics.Spacing.xs)
            .glassEffect(.regular, in: Capsule())
    }

    func catalogSurfaceCard() -> some View {
        self
            .padding(CatalogMetrics.Spacing.lg)
            .glassEffect(.regular, in: CatalogShapes.section)
    }
}

extension View {
    func catalogSurfaceTile(tint: Color? = nil) -> some View {
        self
            .padding(CatalogMetrics.Spacing.md)
            .glassEffect(Glass.regular.tint(tint), in: CatalogShapes.tile)
    }

    func catalogSurfaceTile<Media: View>(
        tint: Color? = nil,
        @ViewBuilder media: () -> Media
    ) -> some View {
        self
            .padding(CatalogMetrics.Spacing.md)
            .background {
                ZStack {
                    media()

                    LinearGradient(
                        colors: [
                            CatalogMediaContrast.scrimMedium,
                            CatalogMediaContrast.scrimStrong
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(CatalogShapes.tile)
            }
            .glassEffect(Glass.regular.tint(tint), in: CatalogShapes.tile)
    }
}
