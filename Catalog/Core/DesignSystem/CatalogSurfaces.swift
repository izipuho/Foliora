import SwiftUI

extension View {
    func catalogSurfaceCapsule() -> some View {
        self
            .padding(.horizontal, CatalogMetrics.Spacing.md)
            .padding(.vertical, CatalogMetrics.Spacing.xs)
            .glassEffect(.regular.interactive(), in: CatalogShapes.capsule)
    }

    func catalogSurfaceCard(
        cardMetrics: CatalogCardLayoutMode.CardMetrics? = nil
    ) -> some View {
        let shape = cardMetrics.map { CatalogShapes.card(cornerRadius: $0.cornerRadius) } ?? CatalogShapes.section

        return self
            .padding(cardMetrics?.cardPadding ?? CatalogMetrics.Spacing.lg)
            .glassEffect(.regular.interactive(), in: shape)
    }

    func catalogSurfaceCard<Media: View>(
        tint: Color? = nil,
        cardMetrics: CatalogCardLayoutMode.CardMetrics? = nil,
        @ViewBuilder media: () -> Media
    ) -> some View {
        let shape = cardMetrics.map { CatalogShapes.card(cornerRadius: $0.cornerRadius) } ?? CatalogShapes.section

        return self
            .padding(cardMetrics?.cardPadding ?? CatalogMetrics.Spacing.lg)
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
                .clipShape(shape)
            }
            .glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
    }

    func catalogSurfaceTile() -> some View {
        self
            .padding(CatalogMetrics.Spacing.md)
            .glassEffect(.regular, in: CatalogShapes.tile)
    }

    func catalogSurfaceCTATile(tint: Color) -> some View {
        self
            .padding(CatalogMetrics.Spacing.md)
            .background {
                tint
                    .opacity(0.12)
                    .clipShape(CatalogShapes.tile)
            }
            .glassEffect(.regular.interactive(), in: CatalogShapes.tile)
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
