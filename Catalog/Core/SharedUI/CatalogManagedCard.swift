import SwiftUI

/// Connects a catalog card to shared selection and Move/Delete management state.
struct CatalogManagedCard<Item: Identifiable, Content: View>: View where Item.ID == UUID {
    let item: Item
    @Binding var state: CatalogCardManagementState<Item>
    let cardSize: CGSize
    let canManage: Bool
    let shouldHandleTap: (Item) -> Bool
    let onOpen: (Item) -> Void
    let selectTitle: String
    let moveTitle: String
    private let content: () -> Content

    init(
        item: Item,
        state: Binding<CatalogCardManagementState<Item>>,
        cardSize: CGSize,
        canManage: Bool,
        shouldHandleTap: @escaping (Item) -> Bool = { _ in true },
        onOpen: @escaping (Item) -> Void,
        selectTitle: String,
        moveTitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.item = item
        self._state = state
        self.cardSize = cardSize
        self.canManage = canManage
        self.shouldHandleTap = shouldHandleTap
        self.onOpen = onOpen
        self.selectTitle = selectTitle
        self.moveTitle = moveTitle
        self.content = content
    }

    var body: some View {
        CatalogInteractiveCard(
            cardSize: cardSize,
            isSelected: state.selectedIDs.contains(item.id),
            isSelectionModeEnabled: state.isSelectionModeEnabled,
            onTap: handleTap,
            onSelect: canManage ? { state.enterSelection(with: item) } : nil,
            selectTitle: selectTitle,
            contextMenu: canManage ? managementMenu : nil,
            content: content
        )
    }

    private func handleTap() {
        guard shouldHandleTap(item) else { return }

        if state.isSelectionModeEnabled {
            state.toggleSelection(of: item)
        } else {
            onOpen(item)
        }
    }

    private var managementMenu: () -> AnyView {
        {
            AnyView(
                CatalogCardManagementMenu(
                    moveTitle: moveTitle,
                    onMove: { state.beginMove(item) },
                    onDelete: { state.beginDelete(item) }
                )
            )
        }
    }
}
