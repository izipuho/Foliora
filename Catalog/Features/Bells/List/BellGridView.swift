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

struct BellGridView<Bell: BellCardDisplayable, ContextMenuContent: View, Preview: View>: View {
    let bells: [Bell]
    let layoutMode: BellGridLayoutMode
    let cardSize: CGSize
    let gridMetrics: BellGridLayoutMode.GridMetrics
    let cardMetrics: BellGridLayoutMode.CardMetrics
    let selectedBellIDs: Set<UUID>
    let isSelectionModeEnabled: Bool
    let onTap: (Bell) -> Void
    let onSelect: ((Bell) -> Void)?
    @ViewBuilder let contextMenu: (Bell) -> ContextMenuContent
    @ViewBuilder let preview: (Bell) -> Preview

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

    private func bellCardButton(_ bell: Bell) -> some View {
        let isSelected = selectedBellIDs.contains(bell.id)
        let shouldShowSelectionOverlay = isSelectionModeEnabled && isSelected

        return Button {
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
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous)
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
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onSelect {
                Button {
                    onSelect(bell)
                } label: {
                    Label(String(localized: "bell.context.select"), systemImage: "checkmark.circle")
                }
            }

            contextMenu(bell)
        } preview: {
            preview(bell)
        }
    }
}
