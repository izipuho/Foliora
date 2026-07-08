import SwiftUI

struct CatalogCardGrid<Content: View>: View {
    typealias LayoutMetrics = (cardSize: CGSize, gridMetrics: CatalogCardLayoutMode.GridMetrics, cardMetrics: CatalogCardLayoutMode.CardMetrics)

    let layoutMode: CatalogCardLayoutMode
    let bottomContentMargin: CGFloat?
    let layoutMetrics: LayoutMetrics?
    let usesGridLayout: Bool
    @ViewBuilder let content: (
        CGSize,
        CatalogCardLayoutMode.GridMetrics,
        CatalogCardLayoutMode.CardMetrics
    ) -> Content

    init(
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: LayoutMetrics? = nil,
        usesGridLayout: Bool = true,
        @ViewBuilder content: @escaping (
            CGSize,
            CatalogCardLayoutMode.GridMetrics,
            CatalogCardLayoutMode.CardMetrics
        ) -> Content
    ) {
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.layoutMetrics = layoutMetrics
        self.usesGridLayout = usesGridLayout
        self.content = content
    }

    var body: some View {
        if let layoutMetrics {
            layoutContent(layoutMetrics)
        } else {
            GeometryReader { proxy in
                let containerWidth = proxy.size.width
                let gridMetrics = layoutMode.gridMetrics(forContainerWidth: containerWidth)
                let cardWidth = layoutMode.cardWidth(forContainerWidth: containerWidth)
                let cardMetrics = layoutMode.cardMetrics(forCardWidth: cardWidth)
                let layoutMetrics = (
                    cardSize: CGSize(width: cardWidth, height: cardMetrics.cardHeight),
                    gridMetrics: gridMetrics,
                    cardMetrics: cardMetrics
                )

                ScrollView {
                    layoutContent(layoutMetrics)
                }
                .contentMargins(.horizontal, nil, for: .scrollContent)
                .contentMargins(.top, nil, for: .scrollContent)
                .contentMargins(.bottom, bottomContentMargin, for: .scrollContent)
            }
        }
    }

    @ViewBuilder
    private func layoutContent(_ metrics: LayoutMetrics) -> some View {
        if usesGridLayout {
            LazyVGrid(columns: gridColumns(cardSize: metrics.cardSize, gridMetrics: metrics.gridMetrics), spacing: metrics.gridMetrics.spacing) {
                content(metrics.cardSize, metrics.gridMetrics, metrics.cardMetrics)
            }
        } else {
            content(metrics.cardSize, metrics.gridMetrics, metrics.cardMetrics)
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
    let layoutMode: CatalogCardLayoutMode
    let screenWidth: CGFloat
    let horizontalPadding: CGFloat
    @ViewBuilder let content: (CGSize, CatalogCardLayoutMode.CardMetrics) -> Content

    init(
        layoutMode: CatalogCardLayoutMode,
        screenWidth: CGFloat,
        horizontalPadding: CGFloat = CatalogMetrics.Spacing.xs,
        @ViewBuilder content: @escaping (CGSize, CatalogCardLayoutMode.CardMetrics) -> Content
    ) {
        self.layoutMode = layoutMode
        self.screenWidth = screenWidth
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    var body: some View {
        let gridMetrics = layoutMode.gridMetrics(forContainerWidth: screenWidth)
        let cardWidth = layoutMode.cardWidth(forContainerWidth: screenWidth)
        let cardMetrics = layoutMode.cardMetrics(forCardWidth: cardWidth)
        let cardSize = CGSize(width: cardWidth, height: cardMetrics.cardHeight)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gridMetrics.spacing) {
                content(cardSize, cardMetrics)
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: cardSize.height)
    }
}
