import SwiftUI

struct BellGridContainerView<Content: View>: View {
    let layoutMode: BellGridLayoutMode
    let bottomContentMargin: CGFloat?
    @ViewBuilder let content: (CGSize) -> Content

    init(
        layoutMode: BellGridLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        @ViewBuilder content: @escaping (CGSize) -> Content
    ) {
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = layoutMode.cardWidth(forContainerWidth: proxy.size.width)
            let cardSize = CGSize(width: cardWidth, height: layoutMode.metrics.cardHeight)

            ScrollView {
                content(cardSize)
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
    let selectedBellIDs: Set<UUID>
    let isSelectionModeEnabled: Bool
    let onTap: (Bell) -> Void
    let onSelect: ((Bell) -> Void)?
    @ViewBuilder let contextMenu: (Bell) -> ContextMenuContent
    @ViewBuilder let preview: (Bell) -> Preview

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: layoutMode.metrics.spacing) {
            ForEach(bells, id: \.id) { bell in
                bellCardButton(bell)
            }
        }
    }

    private var gridColumns: [GridItem] {
        let metrics = layoutMode.metrics

        return Array(
            repeating: GridItem(.fixed(cardSize.width), spacing: metrics.spacing, alignment: .top),
            count: metrics.columnCount
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
                cardSize: cardSize
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
