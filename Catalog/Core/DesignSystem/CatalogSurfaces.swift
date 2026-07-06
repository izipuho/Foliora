import SwiftUI

private enum CatalogSurfaceMetrics {
    static let strokeWidth: CGFloat = 1
}

struct CatalogSurfaceCapsule<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, CatalogMetrics.Spacing.md)
            .padding(.vertical, CatalogMetrics.Spacing.xs)
            .glassEffect(.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            }
    }
}

extension View {
    func catalogSurfaceCard() -> some View {
        self
            .padding(CatalogMetrics.Spacing.lg)
            .glassEffect(.regular, in: CatalogShapes.section)
            .overlay {
                CatalogShapes.section
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceMetrics.strokeWidth)
            }
    }
}

extension View {
    func catalogSurfaceTile(tint: Color? = nil) -> some View {
        self
            .padding(CatalogMetrics.Spacing.md)
            .glassEffect(Glass.regular.tint(tint), in: CatalogShapes.tile)
            .overlay {
                CatalogShapes.tile
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceMetrics.strokeWidth)
            }
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
            .overlay {
                CatalogShapes.tile
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceMetrics.strokeWidth)
            }
    }
}
