import SwiftUI

/// Edits shared and bell-specific fields for multiple selected bells.
struct BellBatchEditView: View {
    let onSave: (ItemBatchEdit, BellBatchEdit) -> Void

    @State private var material: BellMaterial?
    @State private var customMaterialName = ""

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
        }
    }

    private var bellEdit: BellBatchEdit {
        BellBatchEdit(
            material: material,
            customMaterialName: customMaterialName
        )
    }
}

#if DEBUG
#Preview {
    BellBatchEditView { _, _ in }
}
#endif

extension CatalogCardManagementModifier where Item == BellListItem {
    init(
        state: Binding<CatalogCardManagementState<BellListItem>>,
        visibleItems: [BellListItem],
        snapshot: CatalogSnapshot?,
        collection: CollectionSummary?,
        currentLocationID: @escaping (BellListItem) -> UUID?,
        moveTitle: String,
        deleteTitle: String,
        deleteMessage: String,
        selectedTitle: @escaping (Int) -> String,
        canEdit: Bool,
        tint: Color,
        onSaveHome: @escaping (Home, [Location]) -> Void,
        onMove: @escaping ([BellListItem], UUID?) -> Void,
        onDelete: @escaping ([BellListItem]) -> Void,
        onBatchEdit: @escaping ([BellListItem], ItemBatchEdit, BellBatchEdit) -> Void
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
            }
        )
    }
}

extension BellCatalogView {
    func batchEditBells(
        _ bells: [BellListItem],
        itemEdit: ItemBatchEdit,
        bellEdit: BellBatchEdit
    ) {
        guard canEditCollection else { return }

        let updatedRecords = bells.compactMap { bell -> BellRecord? in
            guard let record = catalogSnapshot?.recordsByID[bell.id] else { return nil }
            return BellRecord(
                item: itemEdit.applying(to: record.item),
                details: bellEdit.applying(to: record.details)
            )
        }
        guard !updatedRecords.isEmpty else { return }

        repository.saveBellRecords(updatedRecords)
    }
}
