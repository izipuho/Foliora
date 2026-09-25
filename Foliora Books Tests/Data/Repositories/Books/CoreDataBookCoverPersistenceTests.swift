import CoreData
import Foundation
import Testing
@testable import Foliora_Books

@MainActor
struct CoreDataBookCoverPersistenceTests {
    @Test
    func preservesDedicatedOriginalCoverThroughSaveAndSnapshot() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let repository = CoreDataCatalogRepository(
            context: container.viewContext,
            persistentContainer: nil
        )

        let collectionID = UUID()
        repository.saveCollection(
            Collection(
                id: collectionID,
                homeID: UUID(),
                kind: .books,
                title: "Books",
                notes: ""
            )
        )

        let itemID = UUID()
        let coverData = Data([0x01, 0x02, 0x03, 0x04])
        let cover = MediaAsset(
            id: UUID(),
            itemID: itemID,
            kind: .photo,
            localIdentifier: "original-cover.jpg",
            displayName: "Cover",
            sortOrder: 0,
            fileName: "original-cover.jpg",
            mimeType: "image/jpeg",
            byteSize: coverData.count,
            checksum: "cover-checksum",
            width: 1200,
            height: 1800,
            originalData: coverData
        )

        repository.saveBookRecord(
            BookRecord(
                item: ItemRecord(
                    id: itemID,
                    collectionID: collectionID,
                    locationID: nil,
                    originPlaceID: nil,
                    createdAt: .now,
                    createdBy: "test",
                    title: "Book",
                    notes: "",
                    acquiredYear: nil,
                    condition: .good,
                    acquisitionMethod: .other,
                    isFavorite: false,
                    tags: [],
                    originPlace: nil,
                    storageLocation: nil,
                    storagePath: nil,
                    mediaAssets: []
                ),
                details: BookDetails(
                    itemID: itemID,
                    languageCode: nil,
                    pageCount: nil,
                    publicationYear: nil,
                    volumeNumber: nil,
                    coverImage: cover,
                    contributors: []
                )
            )
        )

        let snapshot = CatalogSnapshot.load(from: container.viewContext)
        let persisted = try #require(snapshot.recordsByID[itemID])
        let persistedCover = try #require(persisted.details.coverImage)

        #expect(persistedCover.id == cover.id)
        #expect(persistedCover.localIdentifier == cover.localIdentifier)
        #expect(persistedCover.originalData == coverData)
        #expect(persistedCover.width == cover.width)
        #expect(persistedCover.height == cover.height)
        #expect(persisted.mediaAssets.isEmpty)
    }
}
