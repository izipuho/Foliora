import CoreData
import Foundation
import Testing
@testable import Foliora_Books

@MainActor
struct CoreDataBookCoverPersistenceTests {
    @Test
    func preservesDedicatedOriginalCoverThroughSaveAndSnapshot() async throws {
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

        let mediaDataLoader = MediaDataLoader(container: container)

        #expect(persistedCover.id == cover.id)
        #expect(persistedCover.originalData == nil)
        #expect(await mediaDataLoader.data(forAssetID: cover.id) == coverData)
        #expect(persistedCover.width == cover.width)
        #expect(persistedCover.height == cover.height)
        #expect(persisted.mediaAssets.isEmpty)

        #expect(
            repository.saveItemRecognition(
                ItemRecognitionRecord(
                    itemID: itemID,
                    photoAssetIDs: [cover.id],
                    evidenceData: Data([0x05]),
                    resultData: Data([0x06])
                )
            )
        )

        let refreshedSnapshot = CatalogSnapshot.load(from: container.viewContext)
        let refreshed = try #require(refreshedSnapshot.recordsByID[itemID])
        let refreshedCover = try #require(refreshed.details.coverImage)

        #expect(refreshedCover.id == cover.id)
        #expect(refreshedCover.originalData == nil)
        #expect(refreshedCover.width == cover.width)
        #expect(refreshedCover.height == cover.height)
        #expect(refreshed.mediaAssets.isEmpty)

        // Saving a snapshot record, which carries no media bytes, must keep the stored bytes.
        repository.saveBookRecord(refreshed)
        #expect(await mediaDataLoader.data(forAssetID: cover.id) == coverData)
    }

    @Test
    func copiedMediaWithoutBytesTakesStoredBytesByChecksum() async throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let repository = CoreDataCatalogRepository(
            context: container.viewContext,
            persistentContainer: nil
        )

        let collectionID = UUID()
        repository.saveCollection(
            Collection(id: collectionID, homeID: UUID(), kind: .books, title: "Books", notes: "")
        )

        let photoData = Data([0x0A, 0x0B, 0x0C])
        let sourcePhoto = makePhoto(checksum: "shared-checksum", originalData: photoData)
        let sourceItemID = UUID()
        repository.saveBookRecord(makeBook(itemID: sourceItemID, collectionID: collectionID, mediaAssets: [sourcePhoto]))

        // A copy under a new ID, as materialized from a snapshot record: same checksum, no bytes.
        let copiedPhoto = makePhoto(checksum: "shared-checksum", originalData: nil)
        let copyItemID = UUID()
        repository.saveBookRecord(makeBook(itemID: copyItemID, collectionID: collectionID, mediaAssets: [copiedPhoto]))

        let mediaDataLoader = MediaDataLoader(container: container)
        #expect(await mediaDataLoader.data(forAssetID: copiedPhoto.id) == photoData)
    }

    @Test
    func importPreservesDedicatedCoverAndBookDetails() async throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
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
        repository.saveItemRecord(
            ItemRecord(
                id: itemID,
                collectionID: collectionID,
                kind: .books,
                locationID: nil,
                originPlaceID: nil,
                createdAt: .now,
                createdBy: "test",
                title: "Imported Book",
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
            )
        )

        let collectionRequest = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
        collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as NSUUID)
        let collectionEntity = try #require(context.fetch(collectionRequest).first)

        let itemRequest = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
        itemRequest.predicate = NSPredicate(format: "id == %@", itemID as NSUUID)
        let itemEntity = try #require(context.fetch(itemRequest).first)

        let coverData = Data([0x11, 0x22, 0x33, 0x44])
        let cover = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            displayName: "Imported Cover",
            sortOrder: 4,
            fileName: "cover.jpg",
            mimeType: "image/jpeg",
            byteSize: coverData.count,
            checksum: "import-cover-checksum",
            width: 900,
            height: 1400,
            originalData: coverData
        )
        let identifier = BookIdentifier(type: .isbn13, value: "9781234567897")
        let sourceDetails = BookDetails(
            itemID: itemID,
            subtitle: "Imported subtitle",
            languageCode: "en",
            genre: "Fiction",
            pageCount: 320,
            publicationYear: 2026,
            volumeNumber: 2,
            coverImage: cover,
            contributors: [],
            identifiers: [identifier]
        )
        let bookPayload = BookCatalogTransferPayload(
            items: [
                BookCatalogTransferItem(
                    itemID: itemID,
                    details: sourceDetails
                )
            ]
        )
        let payload = CatalogDomainPayload(
            domain: BookCatalogTransferPayload.domain,
            version: BookCatalogTransferPayload.version,
            data: try JSONEncoder().encode(bookPayload)
        )

        BookCatalogTransferAdapter().applyPayloads(
            [payload],
            collectionEntitiesByID: [collectionID: collectionEntity],
            itemEntitiesByID: [itemID: itemEntity],
            in: context
        )

        let snapshot = CatalogSnapshot.load(from: context)
        let imported = try #require(snapshot.recordsByID[itemID])
        let importedCover = try #require(imported.details.coverImage)
        let mediaDataLoader = MediaDataLoader(container: container)

        #expect(imported.details.subtitle == sourceDetails.subtitle)
        #expect(imported.details.languageCode == sourceDetails.languageCode)
        #expect(imported.details.genre == sourceDetails.genre)
        #expect(imported.details.pageCount == sourceDetails.pageCount)
        #expect(imported.details.publicationYear == sourceDetails.publicationYear)
        #expect(imported.details.volumeNumber == sourceDetails.volumeNumber)
        #expect(imported.details.identifiers == [identifier])
        #expect(importedCover.id == cover.id)
        #expect(importedCover.sortOrder == 0)
        #expect(importedCover.width == cover.width)
        #expect(importedCover.height == cover.height)
        #expect(await mediaDataLoader.data(forAssetID: cover.id) == coverData)
    }

    private func makePhoto(checksum: String, originalData: Data?) -> MediaAsset {
        MediaAsset(
            id: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            byteSize: originalData?.count,
            checksum: checksum,
            originalData: originalData
        )
    }

    private func makeBook(itemID: UUID, collectionID: UUID, mediaAssets: [MediaAsset]) -> BookRecord {
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
                mediaAssets: mediaAssets
            ),
            details: BookDetails(
                itemID: itemID,
                languageCode: nil,
                pageCount: nil,
                publicationYear: nil,
                volumeNumber: nil,
                coverImage: nil,
                contributors: []
            )
        )
    }
}
