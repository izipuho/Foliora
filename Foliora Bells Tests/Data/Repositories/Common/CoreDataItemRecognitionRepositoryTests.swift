import CoreData
import Foundation
import Testing
@testable import Foliora_Bells

@MainActor
struct CoreDataItemRecognitionRepositoryTests {
    @Test
    func recognitionRoundTripsInSameStoreAsItemAndCanBeDeleted() throws {
        let (context, repository, collectionID) = try makeRepository()
        let itemID = UUID()
        repository.saveItemRecord(makeItem(id: itemID, collectionID: collectionID))

        let firstPhotoID = UUID()
        let secondPhotoID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = ItemRecognitionRecord(
            itemID: itemID,
            photoAssetIDs: [firstPhotoID, secondPhotoID],
            evidenceData: Data([0x01, 0x02]),
            resultData: Data([0x03, 0x04]),
            updatedAt: updatedAt
        )

        #expect(repository.saveItemRecognition(record))

        let item = try #require(
            try fetchEntities(named: "ItemEntity", from: context)
                .first { ($0.value(forKey: "id") as? UUID) == itemID }
        )
        let recognition = try #require(item.value(forKey: "recognition") as? NSManagedObject)

        #expect(recognition.objectID.persistentStore == item.objectID.persistentStore)
        #expect(repository.itemRecognition(for: itemID) == record)

        let updatedRecord = ItemRecognitionRecord(
            itemID: itemID,
            photoAssetIDs: [secondPhotoID],
            evidenceData: Data([0x05]),
            resultData: Data([0x06]),
            schemaVersion: 2,
            updatedAt: updatedAt.addingTimeInterval(60)
        )

        #expect(repository.saveItemRecognition(updatedRecord))
        #expect(try fetchEntities(named: "ItemRecognitionEntity", from: context).count == 1)
        #expect(repository.itemRecognition(for: itemID) == updatedRecord)

        repository.deleteItemRecognition(for: itemID)

        #expect(try fetchEntities(named: "ItemRecognitionEntity", from: context).isEmpty)
        #expect(repository.itemRecognition(for: itemID) == nil)
    }

    @Test
    func recognitionIsNotCreatedBeforeItemExists() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let repository = CoreDataCatalogRepository(
            context: container.viewContext,
            persistentContainer: nil
        )
        let record = ItemRecognitionRecord(
            itemID: UUID(),
            photoAssetIDs: [UUID()],
            evidenceData: Data([0x01]),
            resultData: Data([0x02])
        )

        #expect(!repository.saveItemRecognition(record))
        #expect(try fetchEntities(named: "ItemRecognitionEntity", from: container.viewContext).isEmpty)
    }

    private func makeRepository() throws -> (
        context: NSManagedObjectContext,
        repository: CoreDataCatalogRepository,
        collectionID: UUID
    ) {
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
                kind: .bells,
                title: "Recognition test",
                notes: ""
            )
        )
        return (context, repository, collectionID)
    }

    private func makeItem(id: UUID, collectionID: UUID) -> ItemRecord {
        ItemRecord(
            id: id,
            collectionID: collectionID,
            locationID: nil,
            originPlaceID: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: "test",
            title: "Test item",
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .bought,
            isFavorite: false,
            tags: [],
            originPlace: nil,
            storageLocation: nil,
            storagePath: nil,
            mediaAssets: []
        )
    }

    private func fetchEntities(
        named entityName: String,
        from context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entityName))
    }
}
