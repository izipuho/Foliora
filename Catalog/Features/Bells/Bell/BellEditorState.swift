import Foundation

/// Holds the editable bell draft and bell-specific validation needed to persist it.
struct BellEditorState {
    var itemState: ItemEditorState
    var material: BellMaterial
    var customMaterialName: String
    var selectedOriginPlace: Place?

    init(
        bell: BellRecord?,
        initialMediaAssets: [MediaAsset]
    ) {
        itemState = ItemEditorState(
            item: bell?.item,
            initialMediaAssets: initialMediaAssets
        )
        material = bell?.details.material ?? .unknown
        customMaterialName = bell?.details.customMaterialName ?? ""
        selectedOriginPlace = bell?.originPlace
    }

    var title: String {
        get { itemState.title }
        set { itemState.title = newValue }
    }

    var notes: String {
        get { itemState.notes }
        set { itemState.notes = newValue }
    }

    var condition: ItemCondition {
        get { itemState.condition }
        set { itemState.condition = newValue }
    }

    var acquisitionMethod: AcquisitionMethod {
        get { itemState.acquisitionMethod }
        set { itemState.acquisitionMethod = newValue }
    }

    var selectedLocationID: UUID? {
        get { itemState.selectedLocationID }
        set { itemState.selectedLocationID = newValue }
    }

    var tags: [String] {
        get { itemState.tags }
        set { itemState.tags = newValue }
    }

    var mediaAssets: [MediaAsset] {
        get { itemState.mediaAssets }
        set { itemState.mediaAssets = newValue }
    }

    var selectedAcquiredYearOption: String {
        get { itemState.selectedAcquiredYearOption }
        set { itemState.selectedAcquiredYearOption = newValue }
    }

    var isTitleValid: Bool {
        itemState.isTitleValid
    }

    var canSave: Bool {
        isTitleValid
    }

    func makeBell(
        itemID: UUID,
        collectionID: UUID,
        existingBell: BellRecord?,
        storageLocation: Location?,
        storagePath: StoragePath?,
        createdAt: Date? = nil,
        createdBy: String? = nil
    ) -> BellRecord {
        let trimmedCustomMaterialName = customMaterialName.trimmingCharacters(in: .whitespacesAndNewlines)

        return BellRecord(
            item: itemState.makeItemRecord(
                itemID: itemID,
                collectionID: collectionID,
                kind: .bells,
                createdAt: existingBell?.createdAt ?? createdAt ?? .now,
                createdBy: existingBell?.createdBy ?? createdBy ?? "You",
                isFavorite: existingBell?.isFavorite ?? false,
                originPlaceID: selectedOriginPlace?.id,
                originPlace: selectedOriginPlace,
                storageLocation: storageLocation,
                storagePath: storagePath
            ),
            details: BellDetails(
                itemID: itemID,
                material: material,
                customMaterialName: material == .other ? trimmedCustomMaterialName : nil
            )
        )
    }
}
