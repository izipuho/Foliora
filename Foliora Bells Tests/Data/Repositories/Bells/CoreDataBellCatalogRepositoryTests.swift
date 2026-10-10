import CoreData
import Foundation
import Testing
@testable import Foliora_Bells

@MainActor
struct CoreDataBellCatalogRepositoryTests {
    @Test
    func saveBellRecordPersistsLinkedItemAndBellDetails() throws {
        let (context, repository, collectionID) = try makeRepository()
        let bell = makeBell(
            collectionID: collectionID,
            title: "Test bell",
            notes: "Stored note",
            acquiredYear: 2024,
            condition: .mint,
            acquisitionMethod: .gifted,
            isFavorite: true,
            tags: ["travel", "small"],
            material: .other,
            customMaterialName: "Pewter"
        )

        repository.saveBellRecord(bell)

        let itemEntities = try fetchEntities(named: "ItemEntity", from: context)
        let itemEntity = try #require(
            itemEntities.first { ($0.value(forKey: "id") as? UUID) == bell.id }
        )
        let bellEntities = try fetchEntities(named: "BellEntity", from: context)
        let bellEntity = try #require(bellEntities.first)
        let linkedItem = try #require(bellEntity.value(forKey: "item") as? NSManagedObject)
        let inverseBell = try #require(itemEntity.value(forKey: "bell") as? NSManagedObject)

        #expect(linkedItem.objectID == itemEntity.objectID)
        #expect(inverseBell.objectID == bellEntity.objectID)
        #expect(bellEntity.value(forKey: "material") as? String == BellMaterial.other.rawValue)
        #expect(bellEntity.value(forKey: "customMaterialName") as? String == "Pewter")

        let persisted = try #require(CatalogSnapshot.load(from: context).recordsByID[bell.id])
        #expect(persisted.title == "Test bell")
        #expect(persisted.notes == "Stored note")
        #expect(persisted.acquiredYear == 2024)
        #expect(persisted.condition == .mint)
        #expect(persisted.acquisitionMethod == .gifted)
        #expect(persisted.isFavorite)
        #expect(persisted.tags == ["travel", "small"])
        #expect(persisted.details.material == .other)
        #expect(persisted.details.customMaterialName == "Pewter")
    }

    @Test
    func saveBellRecordUpdatesExistingEntitiesWithoutCreatingDuplicates() throws {
        let (context, repository, collectionID) = try makeRepository()
        let original = makeBell(
            collectionID: collectionID,
            title: "Original",
            material: .brass
        )
        repository.saveBellRecord(original)

        var updatedItem = original.item
        updatedItem.title = "Updated"
        updatedItem.notes = "Updated note"
        updatedItem.condition = .damaged
        updatedItem.isFavorite = true
        let updated = BellRecord(
            item: updatedItem,
            details: BellDetails(
                itemID: original.id,
                material: .bronze,
                customMaterialName: nil
            )
        )

        repository.saveBellRecord(updated)

        let itemEntities = try fetchEntities(named: "ItemEntity", from: context)
            .filter { ($0.value(forKey: "id") as? UUID) == original.id }
        let bellEntities = try fetchEntities(named: "BellEntity", from: context)

        #expect(itemEntities.count == 1)
        #expect(bellEntities.count == 1)

        let persisted = try #require(CatalogSnapshot.load(from: context).recordsByID[original.id])
        #expect(persisted.title == "Updated")
        #expect(persisted.notes == "Updated note")
        #expect(persisted.condition == .damaged)
        #expect(persisted.isFavorite)
        #expect(persisted.details.material == .bronze)
        #expect(persisted.details.customMaterialName == nil)
    }

    @Test
    func saveBellRecordsPersistsWholeBatch() throws {
        let (context, repository, collectionID) = try makeRepository()
        let first = makeBell(
            collectionID: collectionID,
            title: "First",
            material: .ceramic
        )
        let second = makeBell(
            collectionID: collectionID,
            title: "Second",
            material: .glass
        )

        repository.saveBellRecords([first, second])

        let snapshot = CatalogSnapshot.load(from: context)
        let persistedIDs = Set(
            snapshot.bellRecords
                .filter { $0.item.collectionID == collectionID }
                .map(\.id)
        )

        #expect(persistedIDs == Set([first.id, second.id]))
        #expect(try fetchEntities(named: "ItemEntity", from: context).count == 2)
        #expect(try fetchEntities(named: "BellEntity", from: context).count == 2)
    }

    @Test
    func deleteBellRecordDeletesItemBellAndOrphanTags() throws {
        let (context, repository, collectionID) = try makeRepository()
        let bell = makeBell(
            collectionID: collectionID,
            title: "Delete me",
            tags: ["rare", "travel"],
            material: .silver
        )
        repository.saveBellRecord(bell)

        #expect(try fetchEntities(named: "ItemEntity", from: context).count == 1)
        #expect(try fetchEntities(named: "BellEntity", from: context).count == 1)
        #expect(try fetchEntities(named: "ItemTagEntity", from: context).count == 2)

        repository.deleteBellRecord(bellID: bell.id)

        #expect(try fetchEntities(named: "ItemEntity", from: context).isEmpty)
        #expect(try fetchEntities(named: "BellEntity", from: context).isEmpty)
        #expect(try fetchEntities(named: "ItemTagEntity", from: context).isEmpty)
        #expect(CatalogSnapshot.load(from: context).recordsByID[bell.id] == nil)
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
                title: "Test collection",
                notes: ""
            )
        )
        return (context, repository, collectionID)
    }

    private func makeBell(
        id: UUID = UUID(),
        collectionID: UUID,
        title: String,
        notes: String = "",
        acquiredYear: Int? = nil,
        condition: ItemCondition = .good,
        acquisitionMethod: AcquisitionMethod = .bought,
        isFavorite: Bool = false,
        tags: [String] = [],
        material: BellMaterial,
        customMaterialName: String? = nil
    ) -> BellRecord {
        BellRecord(
            item: ItemRecord(
                id: id,
                collectionID: collectionID,
                locationID: nil,
                originPlaceID: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                createdBy: "test",
                title: title,
                notes: notes,
                acquiredYear: acquiredYear,
                condition: condition,
                acquisitionMethod: acquisitionMethod,
                isFavorite: isFavorite,
                tags: tags,
                originPlace: nil,
                storageLocation: nil,
                storagePath: nil,
                mediaAssets: []
            ),
            details: BellDetails(
                itemID: id,
                material: material,
                customMaterialName: customMaterialName
            )
        )
    }

    private func fetchEntities(
        named entityName: String,
        from context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entityName))
    }
}
