import CoreData
import Foundation
import Testing
@testable import Foliora_Bells

@MainActor
struct CoreDataSharedStoreAssignmentTests {
    @Test
    func newBellGraphIsSavedInSharedCollectionStore() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let sharedStore = try #require(
            container.persistentStoreCoordinator.persistentStores.first {
                $0.url?.lastPathComponent == "Shared"
            }
        )

        let collectionID = UUID()
        let collection = NSEntityDescription.insertNewObject(
            forEntityName: "CollectionEntity",
            into: context
        )
        context.assign(collection, to: sharedStore)
        collection.setValue(collectionID, forKey: "id")
        collection.setValue(CollectionKind.bells.rawValue, forKey: "kind")
        collection.setValue("Shared bells", forKey: "title")
        collection.setValue(UUID(), forKey: "homeID")
        try context.save()

        let itemID = UUID()
        let photo = MediaAsset(
            id: UUID(),
            itemID: itemID,
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            checksum: "shared-store-test",
            originalData: Data([0x01, 0x02, 0x03])
        )
        let item = ItemRecord(
            id: itemID,
            collectionID: collectionID,
            locationID: nil,
            originPlaceID: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: "test",
            title: "Shared bell",
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .bought,
            isFavorite: false,
            tags: ["shared"],
            originPlace: nil,
            storageLocation: nil,
            storagePath: nil,
            mediaAssets: [photo]
        )

        repository.saveBellRecord(
            BellRecord(
                item: item,
                details: BellDetails(itemID: itemID, material: .brass, customMaterialName: nil)
            )
        )

        #expect(!context.hasChanges)
        for entityName in ["ItemEntity", "BellEntity", "MediaAssetEntity", "ItemTagEntity"] {
            let entities = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entityName))
            #expect(entities.count == 1, "\(entityName) count")
            #expect(
                entities.allSatisfy { $0.objectID.persistentStore == sharedStore },
                "\(entityName) must be saved in the shared store"
            )
        }
    }

    @Test
    func savingSharedCollectionKeepsOwnerHome() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let sharedStore = try #require(FolioraCoreDataStack.sharedPersistentStore(in: container))

        let ownerHomeID = UUID()
        let collectionID = UUID()
        let collection = NSEntityDescription.insertNewObject(
            forEntityName: "CollectionEntity",
            into: context
        )
        context.assign(collection, to: sharedStore)
        collection.setValue(collectionID, forKey: "id")
        collection.setValue(CollectionKind.bells.rawValue, forKey: "kind")
        collection.setValue("Shared bells", forKey: "title")
        collection.setValue(ownerHomeID, forKey: "homeID")
        collection.setValue("Owner home", forKey: "homeName")
        try context.save()

        let participantHome = Home(id: UUID(), name: "Participant home", notes: "")
        repository.saveHome(participantHome)
        repository.saveLocations(
            [
                Location(
                    id: UUID(),
                    homeID: participantHome.id,
                    parentLocationID: nil,
                    kind: .room,
                    name: "Room",
                    notes: "",
                    sortOrder: nil
                )
            ],
            in: participantHome.id
        )

        repository.saveCollection(
            Collection(
                id: collectionID,
                homeID: participantHome.id,
                kind: .bells,
                title: "Renamed",
                notes: ""
            )
        )

        #expect(!context.hasChanges)
        #expect(collection.value(forKey: "title") as? String == "Renamed")
        #expect(collection.value(forKey: "homeID") as? UUID == ownerHomeID)
        #expect(collection.value(forKey: "homeName") as? String == "Owner home")

        let collectionLocations = try context.fetch(
            NSFetchRequest<NSManagedObject>(entityName: "CollectionLocationEntity")
        )
        #expect(collectionLocations.isEmpty)
    }
}
