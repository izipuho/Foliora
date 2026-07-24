import SwiftUI

struct BellGridView: View {
    let bells: [BellListItem]
    let recordFor: (BellListItem) -> BellRecord?
    let layoutMode: CatalogCardLayoutMode
    let bottomContentMargin: CGFloat?
    let layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics?
    let selectedBellIDs: Set<UUID>
    let isSelectionModeEnabled: Bool
    let onTap: (BellListItem) -> Void
    let onSelect: ((BellListItem) -> Void)?
    let contextMenu: ((BellListItem) -> AnyView)?

    init(
        bells: [BellListItem],
        recordFor: @escaping (BellListItem) -> BellRecord?,
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        selectedBellIDs: Set<UUID>,
        isSelectionModeEnabled: Bool,
        onTap: @escaping (BellListItem) -> Void,
        onSelect: ((BellListItem) -> Void)?,
        contextMenu: ((BellListItem) -> AnyView)? = nil
    ) {
        self.bells = bells
        self.recordFor = recordFor
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.layoutMetrics = layoutMetrics
        self.selectedBellIDs = selectedBellIDs
        self.isSelectionModeEnabled = isSelectionModeEnabled
        self.onTap = onTap
        self.onSelect = onSelect
        self.contextMenu = contextMenu
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics
        ) { cardSize, _, cardMetrics in
            ForEach(bells, id: \.id) { bell in
                if let record = recordFor(bell) {
                    bellCardButton(bell, record: record, cardSize: cardSize, cardMetrics: cardMetrics)
                }
            }
        }
    }

    @ViewBuilder
    private func bellCardButton(
        _ bell: BellListItem,
        record: BellRecord,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) -> some View {
        let isSelected = selectedBellIDs.contains(bell.id)
        let shouldShowSelectionOverlay = isSelectionModeEnabled && isSelected
        let style = CatalogCardContentStyle.style(for: layoutMode)

        let button = Button {
            onTap(bell)
        } label: {
            BellCardView(
                bell: record,
                style: style,
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
        .frame(width: cardSize.width, height: cardSize.height)
        .contentShape(Rectangle())

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
