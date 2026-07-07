import SwiftUI

struct BellGridContainerView<Content: View>: View {
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
            let adaptiveGridMetrics = layoutMode.gridMetrics(forContainerWidth: containerWidth)
            let cardWidth = layoutMode.cardWidth(forContainerWidth: containerWidth)
            let adaptiveCardMetrics = layoutMode.cardMetrics(forCardWidth: cardWidth)
            let cardSize = CGSize(width: cardWidth, height: adaptiveCardMetrics.cardHeight)

            ScrollView {
                content(cardSize, adaptiveGridMetrics, adaptiveCardMetrics)
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, bottomContentMargin, for: .scrollContent)
        }
    }
}

struct BellGridView<Bell: BellCardDisplayable>: View {
    let bells: [Bell]
    let layoutMode: CatalogCardLayoutMode
    let cardSize: CGSize
    let gridMetrics: CatalogCardLayoutMode.GridMetrics
    let cardMetrics: CatalogCardLayoutMode.CardMetrics
    let selectedBellIDs: Set<UUID>
    let isSelectionModeEnabled: Bool
    let onTap: (Bell) -> Void
    let onSelect: ((Bell) -> Void)?
    let contextMenu: ((Bell) -> AnyView)?

    init(
        bells: [Bell],
        layoutMode: CatalogCardLayoutMode,
        cardSize: CGSize,
        gridMetrics: CatalogCardLayoutMode.GridMetrics,
        cardMetrics: CatalogCardLayoutMode.CardMetrics,
        selectedBellIDs: Set<UUID>,
        isSelectionModeEnabled: Bool,
        onTap: @escaping (Bell) -> Void,
        onSelect: ((Bell) -> Void)?,
        contextMenu: ((Bell) -> AnyView)? = nil
    ) {
        self.bells = bells
        self.layoutMode = layoutMode
        self.cardSize = cardSize
        self.gridMetrics = gridMetrics
        self.cardMetrics = cardMetrics
        self.selectedBellIDs = selectedBellIDs
        self.isSelectionModeEnabled = isSelectionModeEnabled
        self.onTap = onTap
        self.onSelect = onSelect
        self.contextMenu = contextMenu
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: gridMetrics.spacing) {
            ForEach(bells, id: \.id) { bell in
                bellCardButton(bell)
            }
        }
    }

    private var gridColumns: [GridItem] {
        return Array(
            repeating: GridItem(.fixed(cardSize.width), spacing: gridMetrics.spacing, alignment: .top),
            count: gridMetrics.columnCount
        )
    }

    @ViewBuilder
    private func bellCardButton(_ bell: Bell) -> some View {
        let isSelected = selectedBellIDs.contains(bell.id)
        let shouldShowSelectionOverlay = isSelectionModeEnabled && isSelected

        let button = Button {
            onTap(bell)
        } label: {
            BellCardView(
                bell: bell,
                layoutMode: layoutMode,
                cardSize: cardSize,
                cardMetrics: cardMetrics
            )
            .overlay {
                if shouldShowSelectionOverlay {
                    CatalogShapes.medium
                        .fill(CatalogMediaContrast.scrimMedium)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowSelectionOverlay {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                        .frame(width: 20, height: 20)
                        .background(CatalogSemanticColors.info, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(CatalogMediaContrast.onMediaPrimary.opacity(0.9), lineWidth: 2)
                        }
                        .padding(CatalogMetrics.Spacing.sm)
                }
            }
        }
        .buttonStyle(.plain)

        if let contextMenu {
            button
                .contextMenu {
                    if let onSelect {
                        Button {
                            onSelect(bell)
                        } label: {
                            Label(String(localized: "bell.context.select"), systemImage: "checkmark.circle")
                        }
                    }

                    contextMenu(bell)
                }
        } else {
            button
        }
    }
}
