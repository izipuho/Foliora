import SwiftUI

/// Displays bell cards using the shared catalog grid mechanics, with optional card management.
struct BellGridView: View {
    let bells: [BellCatalogItem]
    let layoutMode: CatalogCardLayoutMode
    let bottomContentMargin: CGFloat?
    let layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics?
    @Binding var cardManagement: CatalogCardManagementState<BellCatalogItem>
    let canManage: Bool
    let shouldHandleTap: (BellCatalogItem) -> Bool
    let onOpen: (BellCatalogItem) -> Void
    let visibleItems: [BellCatalogItem]
    let deleteTitle: String
    let deleteMessage: String
    let onDelete: ([BellCatalogItem]) -> Void

    init(
        bells: [BellCatalogItem],
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        cardManagement: Binding<CatalogCardManagementState<BellCatalogItem>>,
        canManage: Bool,
        shouldHandleTap: @escaping (BellCatalogItem) -> Bool = { _ in true },
        onOpen: @escaping (BellCatalogItem) -> Void,
        visibleItems: [BellCatalogItem]? = nil,
        deleteTitle: String = "",
        deleteMessage: String = "",
        onDelete: @escaping ([BellCatalogItem]) -> Void = { _ in }
    ) {
        self.bells = bells
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.layoutMetrics = layoutMetrics
        self._cardManagement = cardManagement
        self.canManage = canManage
        self.shouldHandleTap = shouldHandleTap
        self.onOpen = onOpen
        self.visibleItems = visibleItems ?? bells
        self.deleteTitle = deleteTitle
        self.deleteMessage = deleteMessage
        self.onDelete = onDelete
    }

    /// Creates a read-only grid: tapping a card opens it, no context menu or selection.
    init(
        bells: [BellCatalogItem],
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        onBellSelected: ((UUID) -> Void)?
    ) {
        self.init(
            bells: bells,
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics,
            cardManagement: .constant(CatalogCardManagementState()),
            canManage: false,
            onOpen: { bell in
                onBellSelected?(bell.id)
            }
        )
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics
        ) { cardSize, _, cardMetrics in
            ForEach(bells, id: \.id) { bell in
                CatalogInteractiveCard(
                    item: bell,
                    state: $cardManagement,
                    cardSize: cardSize,
                    canManage: canManage,
                    shouldHandleTap: shouldHandleTap,
                    onOpen: onOpen,
                    selectTitle: String(localized: "bell.context.select"),
                    moveTitle: String(localized: "bell.context.move"),
                    visibleItems: visibleItems,
                    deleteTitle: deleteTitle,
                    deleteMessage: deleteMessage,
                    onDelete: onDelete
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
