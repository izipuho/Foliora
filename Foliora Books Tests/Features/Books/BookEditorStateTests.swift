import Foundation
import Testing
@testable import Foliora_Books

struct BookEditorStateTests {
    @Test
    func validatesTitlePageCountVolumeAndCoverGeneration() {
        var state = BookEditorState(book: nil, initialMediaAssets: [])

        #expect(!state.isTitleValid)
        #expect(!state.canSave(isGeneratingCoverImage: false))

        state.title = "  Test Book  "
        state.pageCount = "0"
        #expect(!state.canSave(isGeneratingCoverImage: false))

        state.pageCount = "320"
        #expect(state.canSave(isGeneratingCoverImage: false))

        state.selectedSeries = BookSeries(
            id: UUID(),
            collectionID: UUID(),
            name: "Trilogy",
            totalBookCount: 3
        )
        state.volumeNumber = "4"
        #expect(!state.isVolumeValid)
        #expect(!state.canSave(isGeneratingCoverImage: false))

        state.volumeNumber = "2"
        #expect(state.isVolumeValid)
        #expect(state.canSave(isGeneratingCoverImage: false))
        #expect(!state.canSave(isGeneratingCoverImage: true))
    }

    @Test
    func makeBookNormalizesDraftAndPreservesExistingItemMetadata() {
        let itemID = UUID()
        let collectionID = UUID()
        let homeID = UUID()
        let locationID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1234)
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
        let existing = BookRecord(
            item: ItemRecord(
                id: itemID,
                collectionID: collectionID,
                kind: .books,
                locationID: locationID,
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
                storageLocation: location,
                storagePath: storagePath,
                mediaAssets: []
            ),
            details: BookDetails(
                itemID: itemID,
                languageCode: nil,
                pageCount: nil,
                publicationYear: nil,
                volumeNumber: nil,
                contributors: []
            )
        )

        var state = BookEditorState(book: existing, initialMediaAssets: [])
        state.title = "  New Title  "
        state.notes = "  New Notes  "
        state.subtitle = "  Subtitle  "
        state.languageCode = " EN "
        state.pageCount = " 250 "
        state.volumeNumber = "2"
        state.selectedSeries = nil

        #expect(state.selectedLocationID == locationID)

        let result = state.makeBook(
            itemID: itemID,
            collectionID: UUID(),
            existingBook: existing
        )

        #expect(result.collectionID == collectionID)
        #expect(result.createdAt == createdAt)
        #expect(result.createdBy == "owner")
        #expect(result.isFavorite)
        #expect(result.title == "New Title")
        #expect(result.notes == "New Notes")
        #expect(result.item.locationID == locationID)
        #expect(result.item.storageLocation?.id == locationID)
        #expect(result.item.storagePath?.displayPath == "Room / Shelf")
        #expect(result.details.subtitle == "Subtitle")
        #expect(result.details.languageCode == "en")
        #expect(result.details.pageCount == 250)
        #expect(result.details.volumeNumber == nil)
    }

    @Test
    func publicationYearOptionsIncludeSelectedHistoricYear() {
        var state = BookEditorState(book: nil, initialMediaAssets: [])
        state.selectedPublicationYearOption = "1888"

        #expect(state.publicationYearOptions.contains("1888"))
    }
}
