import Foundation

/// Holds editable fields shared by all catalog item editors.
struct ItemEditorState {
    var title: String
    var notes: String
    var selectedAcquiredYearOption: String
    var condition: ItemCondition
    var acquisitionMethod: AcquisitionMethod
    var selectedLocationID: UUID?
    var tags: [String]
    var mediaAssets: [MediaAsset]

    init(
        item: ItemRecord?,
        initialMediaAssets: [MediaAsset]
    ) {
        title = item?.title ?? ""
        notes = item?.notes ?? ""
        selectedAcquiredYearOption = item?.acquiredYear.map(String.init) ?? String(localized: "common.none")
        condition = item?.condition ?? .good
        acquisitionMethod = item?.acquisitionMethod ?? .bought
        selectedLocationID = item?.locationID
        tags = item?.tags ?? []
        mediaAssets = item?.mediaAssets ?? initialMediaAssets
    }

    var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func makeItemRecord(
        itemID: UUID,
        collectionID: UUID,
        kind: CollectionKind,
        createdAt: Date,
        createdBy: String,
        isFavorite: Bool,
        originPlaceID: UUID?,
        originPlace: Place?,
        storageLocation: Location?,
        storagePath: StoragePath?
    ) -> ItemRecord {
        let normalizedMediaAssets = mediaAssets.enumerated().map { index, asset in
            asset.with(itemID: itemID, sortOrder: index)
        }

        return ItemRecord(
            id: itemID,
            collectionID: collectionID,
            kind: kind,
            locationID: selectedLocationID,
            originPlaceID: originPlaceID,
            createdAt: createdAt,
            createdBy: createdBy,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            acquiredYear: Int(selectedAcquiredYearOption),
            condition: condition,
            acquisitionMethod: acquisitionMethod,
            isFavorite: isFavorite,
            tags: tags,
            originPlace: originPlace,
            storageLocation: storageLocation,
            storagePath: storagePath,
            mediaAssets: normalizedMediaAssets
        )
    }
}
