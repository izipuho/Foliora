import SwiftUI

private enum CatalogSurfaceMetrics {
    static let strokeWidth: CGFloat = 1
    static let ctaStrokeWidth: CGFloat = 1.5
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
            .background {
                Capsule()
                    .fill(.thinMaterial)
            }
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
            .background(
                CatalogShapes.section
                    .fill(.regularMaterial)
            )
            .overlay {
                CatalogShapes.section
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceMetrics.strokeWidth)
            }
    }
}

extension View {
    func catalogSurfaceTile() -> some View {
        self
            .padding(CatalogMetrics.Spacing.md)
            .background(.regularMaterial, in: CatalogShapes.tile)
            .overlay {
                CatalogShapes.tile
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceMetrics.strokeWidth)
            }
    }

    func catalogSurfaceTile<Media: View>(
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
            .overlay {
                CatalogShapes.tile
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: CatalogSurfaceMetrics.strokeWidth)
            }
    }

    //func catalogSurfaceTileCTA(accentColor: Color) -> some View {
    //    self
    //        .padding(CatalogMetrics.Spacing.md)
    //        .background(
    //            CatalogShapes.tile
    //                .fill(accentColor.opacity(0.08))
    //        )
    //        .overlay {
    //            CatalogShapes.tile
    //                .stroke(
    //                    accentColor.opacity(0.38),
    //                    style: StrokeStyle(
    //                        lineWidth: CatalogSurfaceMetrics.ctaStrokeWidth,
    //                        dash: [6, 6]
    //                    )
    //                )
    //        }
    //}
}
