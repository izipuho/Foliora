import Foundation

/// Holds the editable bell draft and the validation needed to persist it.
struct BellEditorState {
    var title: String
    var notes: String
    var condition: ItemCondition
    var acquisitionMethod: AcquisitionMethod
    var material: BellMaterial
    var customMaterialName: String
    var selectedOriginPlace: Place?
    var selectedLocationID: UUID?
    var tags: [String]
    var mediaAssets: [MediaAsset]
    var selectedAcquiredYearOption: String

    init(
        bell: BellRecord?,
        initialMediaAssets: [MediaAsset]
    ) {
        title = bell?.title ?? ""
        notes = bell?.notes ?? ""
        condition = bell?.condition ?? .good
        acquisitionMethod = bell?.acquisitionMethod ?? .bought
        material = bell?.details.material ?? .unknown
        customMaterialName = bell?.details.customMaterialName ?? ""
        selectedOriginPlace = bell?.originPlace
        selectedLocationID = bell?.item.locationID
        tags = bell?.tags ?? []
        mediaAssets = bell?.mediaAssets ?? initialMediaAssets
        selectedAcquiredYearOption = bell?.acquiredYear.map(String.init) ?? String(localized: "common.none")
    }

    var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSave: Bool {
        isTitleValid
    }

    func makeBell(
        itemID: UUID,
        collectionID: UUID,
        existingBell: BellRecord?,
        availableLocations: [Location]
    ) -> BellRecord {
        let location = availableLocations.first { $0.id == selectedLocationID }
        let normalizedMediaAssets = mediaAssets.enumerated().map { index, asset in
            asset.with(itemID: itemID, sortOrder: index)
        }
        let trimmedCustomMaterialName = customMaterialName.trimmingCharacters(in: .whitespacesAndNewlines)

        return BellRecord(
            item: ItemRecord(
                id: itemID,
                collectionID: collectionID,
                locationID: selectedLocationID,
                originPlaceID: selectedOriginPlace?.id,
                createdAt: existingBell?.createdAt ?? .now,
                createdBy: "You",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                acquiredYear: Int(selectedAcquiredYearOption),
                condition: condition,
                acquisitionMethod: acquisitionMethod,
                isFavorite: existingBell?.isFavorite ?? false,
                tags: tags,
                originPlace: selectedOriginPlace,
                storageLocation: location,
                storagePath: location.map { Self.storagePath(for: $0, in: availableLocations) },
                mediaAssets: normalizedMediaAssets
            ),
            details: BellDetails(
                itemID: itemID,
                material: material,
                customMaterialName: material == .other ? trimmedCustomMaterialName : nil
            )
        )
    }

    private static func storagePath(for location: Location, in locations: [Location]) -> StoragePath {
        let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        var components = [
            StoragePath.Component(
                kind: location.kind,
                name: location.name
            )
        ]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            components.insert(
                StoragePath.Component(
                    kind: parent.kind,
                    name: parent.name
                ),
                at: 0
            )
            currentParentID = parent.parentLocationID
        }

        return StoragePath(components: components)
    }
}
