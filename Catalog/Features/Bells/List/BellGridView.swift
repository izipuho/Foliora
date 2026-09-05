import SwiftUI

/// Displays the bell grid view interface.
struct BellGridView: View {
    let bells: [BellListItem]
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
                CatalogInteractiveCard(
                    cardSize: cardSize,
                    isSelected: selectedBellIDs.contains(bell.id),
                    isSelectionModeEnabled: isSelectionModeEnabled,
                    onTap: {
                        onTap(bell)
                    },
                    onSelect: onSelect.map { action in
                        { action(bell) }
                    },
                    selectTitle: String(localized: "bell.context.select"),
                    contextMenu: contextMenu.map { menu in
                        { menu(bell) }
                    }
                ) {
                    BellCardView(
                        bell: bell,
                        style: CatalogCardContentStyle.style(for: layoutMode),
                        cardSize: cardSize,
                        cardMetrics: cardMetrics
                    )
                }
            }
        }
    }
}
