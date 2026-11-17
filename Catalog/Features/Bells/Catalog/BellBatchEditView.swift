import SwiftUI

/// Edits shared and bell-specific fields for multiple selected bells.
struct BellBatchEditView: View {
    let onSave: (ItemBatchEdit, BellBatchEdit) -> Void

    @State private var material: BellMaterial?
    @State private var customMaterialName = ""
    @State private var size: BellSize?

    var body: some View {
        CatalogBatchEditView(
            isDomainEditEmpty: bellEdit.isEmpty,
            onSave: { itemEdit in
                onSave(itemEdit, bellEdit)
            }
        ) {
            Section {
                Picker(String(localized: "common.field.material"), selection: $material) {
                    Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                        .tag(nil as BellMaterial?)
                    ForEach(BellMaterial.allCases) { value in
                        Text(value.displayName)
                            .tag(Optional(value))
                    }
                }

                if material == .other {
                    TextField(
                        String(localized: "editor.material.custom"),
                        text: $customMaterialName
                    )
                }
            } header: {
                Text(String(localized: "common.field.material"))
            }

            Section {
                Picker(String(localized: "common.field.size"), selection: $size) {
                    Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                        .tag(nil as BellSize?)
                    ForEach(BellSize.allCases) { value in
                        Text(value.displayName)
                            .tag(Optional(value))
                    }
                }
            } header: {
                Text(String(localized: "common.field.size"))
            }
        }
    }

    private var bellEdit: BellBatchEdit {
        BellBatchEdit(
            material: material,
            customMaterialName: customMaterialName,
            size: size
        )
    }
}

#if DEBUG
#Preview {
    BellBatchEditView { _, _ in }
}
#endif

extension CatalogCardManagementModifier where Item == BellCatalogItem {
    init(
        state: Binding<CatalogCardManagementState<BellCatalogItem>>,
        visibleItems: [BellCatalogItem],
        snapshot: CatalogSnapshot?,
        collection: CollectionSummary?,
        currentLocationID: @escaping (BellCatalogItem) -> UUID?,
        moveTitle: String,
        deleteTitle: String,
        deleteMessage: String,
        selectedTitle: @escaping (Int) -> String,
        canEdit: Bool,
        tint: Color,
        onSaveHome: @escaping (Home, [Location]) -> Void,
        onMove: @escaping ([BellCatalogItem], UUID?) -> Void,
        onDelete: @escaping ([BellCatalogItem]) -> Void,
        onBatchEdit: @escaping ([BellCatalogItem], ItemBatchEdit, BellBatchEdit) -> Void,
        showsSelectButton: Bool = false
    ) {
        self.init(
            state: state,
            visibleItems: visibleItems,
            snapshot: snapshot,
            collection: collection,
            currentLocationID: currentLocationID,
            moveTitle: moveTitle,
            deleteTitle: deleteTitle,
            deleteMessage: deleteMessage,
            selectedTitle: selectedTitle,
            canEdit: canEdit,
            tint: tint,
            onSaveHome: onSaveHome,
            onMove: onMove,
            onDelete: onDelete,
            batchEditContent: {
                AnyView(
                    BellBatchEditView { itemEdit, bellEdit in
                        onBatchEdit(
                            state.wrappedValue.selectedItems(in: visibleItems),
                            itemEdit,
                            bellEdit
                        )
                        state.wrappedValue.completeAction()
                    }
                )
            },
            showsSelectButton: showsSelectButton
        )
    }
}

extension CatalogCardManagementModifier where Item == BellCatalogItem {
    /// Standard bell management: shared titles, persistence through `actions`.
    init(
        state: Binding<CatalogCardManagementState<BellCatalogItem>>,
        visibleItems: [BellCatalogItem],
        actions: BellCardActions,
        tint: Color,
        showsSelectButton: Bool = false,
        onMoved: @escaping () -> Void = {},
        onDeleted: @escaping () -> Void = {}
    ) {
        self.init(
            state: state,
            visibleItems: visibleItems,
            snapshot: actions.snapshot,
            collection: actions.collection,
            currentLocationID: { $0.locationID },
            moveTitle: String(localized: "bell.context.move"),
            deleteTitle: String(localized: "bell.context.delete.title"),
            deleteMessage: String(localized: "bell.context.delete.message"),
            selectedTitle: { count in
                String.localizedStringWithFormat(
                    String(localized: "bell_catalog.selection.selected_count"),
                    count
                )
            },
            canEdit: actions.canEdit,
            tint: tint,
            onSaveHome: actions.saveHome,
            onMove: { bells, locationID in
                actions.move(bells, to: locationID)
                onMoved()
            },
            onDelete: { bells in
                actions.delete(bells)
                onDeleted()
            },
            onBatchEdit: actions.batchEdit,
            showsSelectButton: showsSelectButton
        )
    }
}
