import SwiftUI

/// Displays the catalog card grid interface.
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

/// Displays the catalog card strip interface.
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
        .scrollClipDisabled()
        .frame(height: cardSize.height)
    }
}

/// Displays a collapsible horizontal section of catalog cards.
struct CatalogCollapsibleCardSection<Content: View>: View {
    let title: String
    let layoutMode: CatalogCardLayoutMode
    let screenWidth: CGFloat
    @Binding var isCollapsed: Bool
    @ViewBuilder let content: (CGSize, CatalogCardLayoutMode.CardMetrics) -> Content

    init(
        title: String,
        layoutMode: CatalogCardLayoutMode,
        screenWidth: CGFloat,
        isCollapsed: Binding<Bool>,
        @ViewBuilder content: @escaping (CGSize, CatalogCardLayoutMode.CardMetrics) -> Content
    ) {
        self.title = title
        self.layoutMode = layoutMode
        self.screenWidth = screenWidth
        self._isCollapsed = isCollapsed
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: CatalogMetrics.Spacing.sm) {
                    Text(title)
                        .font(CatalogTypography.sectionTitle)
                        .foregroundStyle(.primary)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(CatalogTypography.chipLabel)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.vertical, CatalogMetrics.Spacing.sm)
                .padding(.horizontal, CatalogMetrics.Spacing.md)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 0.5)
                }
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                CatalogCardStrip(
                    layoutMode: layoutMode,
                    screenWidth: screenWidth,
                    horizontalPadding: CatalogMetrics.Insets.screen,
                    content: content
                )
            }
        }
    }
}
