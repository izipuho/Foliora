import SwiftUI

/// Displays the bell grid view interface.
struct BellGridView: View {
    let bells: [BellListItem]
    let layoutMode: CatalogCardLayoutMode
    let bottomContentMargin: CGFloat?
    let layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics?
    @Binding var cardManagement: CatalogCardManagementState<BellListItem>
    let canManage: Bool
    let shouldHandleTap: (BellListItem) -> Bool
    let onOpen: (BellListItem) -> Void

    init(
        bells: [BellListItem],
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        cardManagement: Binding<CatalogCardManagementState<BellListItem>>,
        canManage: Bool,
        shouldHandleTap: @escaping (BellListItem) -> Bool = { _ in true },
        onOpen: @escaping (BellListItem) -> Void
    ) {
        self.bells = bells
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.layoutMetrics = layoutMetrics
        self._cardManagement = cardManagement
        self.canManage = canManage
        self.shouldHandleTap = shouldHandleTap
        self.onOpen = onOpen
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics
        ) { cardSize, _, cardMetrics in
            ForEach(bells, id: \.id) { bell in
                CatalogManagedCard(
                    item: bell,
                    state: $cardManagement,
                    cardSize: cardSize,
                    canManage: canManage,
                    shouldHandleTap: shouldHandleTap,
                    onOpen: onOpen,
                    selectTitle: String(localized: "bell.context.select"),
                    moveTitle: String(localized: "bell.context.move")
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
