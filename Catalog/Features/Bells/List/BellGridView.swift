import SwiftUI

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
