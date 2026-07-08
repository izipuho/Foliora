import SwiftUI

struct CatalogCardGrid<Content: View>: View {
    let layoutMode: CatalogCardLayoutMode
    let bottomContentMargin: CGFloat?
    @ViewBuilder let content: (
        CGSize,
        CatalogCardLayoutMode.GridMetrics,
        CatalogCardLayoutMode.CardMetrics
    ) -> Content

    init(
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        @ViewBuilder content: @escaping (
            CGSize,
            CatalogCardLayoutMode.GridMetrics,
            CatalogCardLayoutMode.CardMetrics
        ) -> Content
    ) {
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let containerWidth = proxy.size.width
            let gridMetrics = layoutMode.gridMetrics(forContainerWidth: containerWidth)
            let cardWidth = layoutMode.cardWidth(forContainerWidth: containerWidth)
            let cardMetrics = layoutMode.cardMetrics(forCardWidth: cardWidth)
            let cardSize = CGSize(width: cardWidth, height: cardMetrics.cardHeight)

            ScrollView {
                LazyVGrid(columns: gridColumns(cardSize: cardSize, gridMetrics: gridMetrics), spacing: gridMetrics.spacing) {
                    content(cardSize, gridMetrics, cardMetrics)
                }
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, bottomContentMargin, for: .scrollContent)
        }
    }

    private func gridColumns(
        cardSize: CGSize,
        gridMetrics: CatalogCardLayoutMode.GridMetrics
    ) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(cardSize.width), spacing: gridMetrics.spacing, alignment: .top),
            count: gridMetrics.columnCount
        )
    }
}

struct CatalogCardStrip<Content: View>: View {
    let cardSize: CGSize
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    @ViewBuilder let content: (CGSize) -> Content

    init(
        cardSize: CGSize,
        spacing: CGFloat,
        horizontalPadding: CGFloat = CatalogMetrics.Spacing.xs,
        @ViewBuilder content: @escaping (CGSize) -> Content
    ) {
        self.cardSize = cardSize
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: spacing) {
                content(cardSize)
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: cardSize.height)
    }
}
