import SwiftUI

/// Displays the bells stored in one location, with the same selection and actions as the catalog.
struct BellStorageItemsView: View {
    let bells: [BellCatalogItem]
    let layoutMode: CatalogCardLayoutMode
    let actions: BellCardActions
    let tint: Color
    let onBellSelected: ((UUID) -> Void)?

    @State private var cardManagement = CatalogCardManagementState<BellCatalogItem>()
    @State private var moveFeedbackToken = 0
    @State private var deleteFeedbackToken = 0

    var body: some View {
        BellGridView(
            bells: bells,
            layoutMode: layoutMode,
            cardManagement: $cardManagement,
            canManage: actions.canEdit,
            onOpen: { bell in
                onBellSelected?(bell.id)
            },
            deleteTitle: String(localized: "bell.context.delete.title"),
            deleteMessage: String(localized: "bell.context.delete.message"),
            onDelete: { bells in
                actions.delete(bells)
                deleteFeedbackToken += 1
            }
        )
        .modifier(
            CatalogCardManagementModifier(
                state: $cardManagement,
                visibleItems: bells,
                actions: actions,
                tint: tint,
                showsSelectButton: true,
                onMoved: { moveFeedbackToken += 1 },
                onDeleted: { deleteFeedbackToken += 1 }
            )
        )
        .sensoryFeedback(.success, trigger: moveFeedbackToken)
        .sensoryFeedback(.warning, trigger: deleteFeedbackToken)
        .onChange(of: bells.map(\.id)) {
            cardManagement.pruneSelection(to: bells)
        }
    }
}
