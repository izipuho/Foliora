import SwiftUI

struct BellGridContainerView<Content: View>: View {
    let layoutMode: BellGridLayoutMode
    let bottomContentMargin: CGFloat?
    @ViewBuilder let content: (
        CGSize,
        BellGridLayoutMode.GridMetrics,
        BellGridLayoutMode.CardMetrics
    ) -> Content

    init(
        layoutMode: BellGridLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        @ViewBuilder content: @escaping (
            CGSize,
            BellGridLayoutMode.GridMetrics,
            BellGridLayoutMode.CardMetrics
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
            let cardWidth = layoutMode.cardWidth(
                forContainerWidth: containerWidth,
                gridMetrics: adaptiveGridMetrics
            )
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
    let layoutMode: BellGridLayoutMode
    let cardSize: CGSize
    let gridMetrics: BellGridLayoutMode.GridMetrics
    let cardMetrics: BellGridLayoutMode.CardMetrics
    let selectedBellIDs: Set<UUID>
    let isSelectionModeEnabled: Bool
    let onTap: (Bell) -> Void
    let onSelect: ((Bell) -> Void)?
    let contextMenu: ((Bell) -> AnyView)?

    init(
        bells: [Bell],
        layoutMode: BellGridLayoutMode,
        cardSize: CGSize,
        gridMetrics: BellGridLayoutMode.GridMetrics,
        cardMetrics: BellGridLayoutMode.CardMetrics,
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
                    RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                        .fill(.black.opacity(0.22))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if shouldShowSelectionOverlay {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blue, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 2)
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
