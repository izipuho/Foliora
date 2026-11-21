import SwiftUI

/// Displays the bells stored in one location, with the same selection and actions as the catalog.
struct BellStorageItemsView: View {
    let bells: [BellCatalogItem]
    let layoutMode: CatalogCardLayoutMode
    let actions: BellCardActions
    let tint: Color
    let onBellSelected: ((UUID) -> Void)?

    @State private var cardManagement = CatalogCardManagementState<BellCatalogItem>()
    @State private var haptics = CatalogHapticTrigger()

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
                haptics.play(.destructiveCompleted)
            }
        )
        .modifier(
            CatalogCardManagementModifier(
                state: $cardManagement,
                visibleItems: bells,
                actions: actions,
                tint: tint,
                showsSelectButton: true,
                onMoved: { haptics.play(.completed) },
                onDeleted: { haptics.play(.destructiveCompleted) }
            )
        )
        .catalogHaptics(haptics)
        .onChange(of: bells.map(\.id)) {
            cardManagement.pruneSelection(to: bells)
        }
    }
}
