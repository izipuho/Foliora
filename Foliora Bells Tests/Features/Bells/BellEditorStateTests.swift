import Foundation
import Testing
@testable import Foliora_Bells

struct BellEditorStateTests {
    @Test
    func validatesRequiredTitle() {
        var state = BellEditorState(bell: nil, initialMediaAssets: [])

        #expect(!state.isTitleValid)
        #expect(!state.canSave)

        state.title = "   "
        #expect(!state.isTitleValid)
        #expect(!state.canSave)

        state.title = "  Test Bell  "
        #expect(state.isTitleValid)
        #expect(state.canSave)
    }

    @Test
    func makeBellNormalizesDraftAndPreservesExistingState() {
        let itemID = UUID()
        let collectionID = UUID()
        let homeID = UUID()
        let locationID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_234)
        let existing = BellRecord(
            item: ItemRecord(
                id: itemID,
                collectionID: collectionID,
                locationID: nil,
                originPlaceID: nil,
                createdAt: createdAt,
                createdBy: "owner",
                title: "Old Title",
                notes: "Old Notes",
                acquiredYear: nil,
                condition: .good,
                acquisitionMethod: .bought,
                isFavorite: true,
                tags: ["existing"],
                originPlace: nil,
                storageLocation: nil,
                storagePath: nil,
                mediaAssets: []
            ),
            details: BellDetails(
                itemID: itemID,
                material: .brass,
                customMaterialName: nil
            )
        )
        let location = Location(
            id: locationID,
            homeID: homeID,
            parentLocationID: nil,
            kind: .shelf,
            name: "Shelf",
            notes: "",
            sortOrder: 0
        )
        let storagePath = StoragePath(
            components: [
                StoragePath.Component(kind: .room, name: "Room"),
                StoragePath.Component(kind: .shelf, name: "Shelf")
            ]
        )

        var state = BellEditorState(bell: existing, initialMediaAssets: [])
        state.title = "  New Title  "
        state.notes = "  New Notes  "
        state.selectedAcquiredYearOption = "2025"
        state.condition = .mint
        state.acquisitionMethod = .gifted
        state.material = .other
        state.customMaterialName = "  Pewter  "
        state.selectedLocationID = locationID
        state.tags = ["travel"]

        let result = state.makeBell(
            itemID: itemID,
            collectionID: collectionID,
            existingBell: existing,
            storageLocation: location,
            storagePath: storagePath
        )

        #expect(result.item.collectionID == collectionID)
        #expect(result.createdAt == createdAt)
        #expect(result.isFavorite)
        #expect(result.title == "New Title")
        #expect(result.notes == "New Notes")
        #expect(result.acquiredYear == 2025)
        #expect(result.condition == .mint)
        #expect(result.acquisitionMethod == .gifted)
        #expect(result.tags == ["travel"])
        #expect(result.details.material == .other)
        #expect(result.details.customMaterialName == "Pewter")
        #expect(result.item.locationID == locationID)
        #expect(result.storageLocation?.id == locationID)
        #expect(result.storagePath?.displayPath == "Room / Shelf")
    }
}
