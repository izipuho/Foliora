import Foundation
import Testing
@testable import Foliora_Bells

struct ItemBatchEditTests {
    private func makeItem(tags: [String]) -> ItemRecord {
        ItemRecord(
            id: UUID(),
            collectionID: UUID(),
            locationID: nil,
            originPlaceID: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: "test",
            title: "Bell",
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .bought,
            isFavorite: false,
            tags: tags,
            originPlace: nil,
            storageLocation: nil,
            storagePath: nil,
            mediaAssets: []
        )
    }

    @Test
    func addedTagsAreAppendedToExistingTags() {
        let updated = ItemBatchEdit(addedTags: ["shelf-3", "glass"])
            .applying(to: makeItem(tags: ["souvenir"]))

        #expect(updated.tags == ["souvenir", "shelf-3", "glass"])
    }

    @Test
    func addedTagsSkipCaseInsensitiveDuplicatesAndBlanks() {
        let updated = ItemBatchEdit(addedTags: ["Souvenir", "  ", " new "])
            .applying(to: makeItem(tags: ["souvenir"]))

        #expect(updated.tags == ["souvenir", "new"])
    }

    @Test
    func addedTagsMakeEditNonEmpty() {
        #expect(ItemBatchEdit().isEmpty)
        #expect(!ItemBatchEdit(addedTags: ["tag"]).isEmpty)
    }
}
