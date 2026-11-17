import CoreData
import Foundation
import Testing
@testable import Foliora_Bells

@MainActor
struct CoreDataLocationDeletionTests {
    @Test
    func removingLocationDeletesUnusedCollectionLocation() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )

        let homeID = UUID()
        let roomID = UUID()
        let shelfID = UUID()

        repository.saveHome(Home(id: homeID, name: "Test Home", notes: ""))
        repository.saveCollection(
            Collection(
                id: UUID(),
                homeID: homeID,
                kind: .bells,
                title: "Test Collection",
                notes: ""
            )
        )

        let room = Location(
            id: roomID,
            homeID: homeID,
            parentLocationID: nil,
            kind: .room,
            name: "Room",
            notes: "",
            sortOrder: 0
        )
        let shelf = Location(
            id: shelfID,
            homeID: homeID,
            parentLocationID: roomID,
            kind: .shelf,
            name: "Shelf",
            notes: "",
            sortOrder: 1
        )
        repository.saveLocations([room, shelf], in: homeID)
        #expect(try collectionLocationSourceIDs(in: context) == [roomID, shelfID])

        repository.saveLocations([room], in: homeID)

        #expect(try collectionLocationSourceIDs(in: context) == [roomID])
    }

    @Test
    func removingNestedLocationsDeletesThemAndArchivesTheOnesWithItems() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )

        let homeID = UUID()
        let collectionID = UUID()
        let roomID = UUID()
        let cabinetID = UUID()
        let emptyShelfID = UUID()
        let usedShelfID = UUID()

        repository.saveHome(Home(id: homeID, name: "Test Home", notes: ""))
        repository.saveCollection(
            Collection(
                id: collectionID,
                homeID: homeID,
                kind: .bells,
                title: "Test Collection",
                notes: ""
            )
        )

        let room = Location(
            id: roomID,
            homeID: homeID,
            parentLocationID: nil,
            kind: .room,
            name: "Room",
            notes: "",
            sortOrder: 0
        )
        let nested = [
            Location(
                id: cabinetID,
                homeID: homeID,
                parentLocationID: roomID,
                kind: .cabinet,
                name: "Cabinet",
                notes: "",
                sortOrder: 1
            ),
            Location(
                id: emptyShelfID,
                homeID: homeID,
                parentLocationID: cabinetID,
                kind: .shelf,
                name: "Empty Shelf",
                notes: "",
                sortOrder: 2
            ),
            Location(
                id: usedShelfID,
                homeID: homeID,
                parentLocationID: cabinetID,
                kind: .shelf,
                name: "Used Shelf",
                notes: "",
                sortOrder: 3
            )
        ]
        repository.saveLocations([room] + nested, in: homeID)
        repository.saveItemRecord(makeItem(collectionID: collectionID, locationID: usedShelfID))

        repository.saveLocations([room], in: homeID)

        let remaining = try collectionLocations(in: context)
        #expect(Set(remaining.keys) == [roomID, usedShelfID])

        let usedShelf = try #require(remaining[usedShelfID])
        #expect(usedShelf.value(forKey: "isArchived") as? Bool == true)
        #expect(usedShelf.value(forKey: "parent") == nil)
        #expect(remaining[roomID]?.value(forKey: "isArchived") as? Bool != true)

        let homeLocations = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "LocationEntity"))
        #expect(homeLocations.compactMap { $0.value(forKey: "id") as? UUID } == [roomID])
    }

    @Test
    func snapshotListsArchivedCollectionLocationsInTheStorageTree() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )

        let homeID = UUID()
        let collectionID = UUID()
        let roomID = UUID()
        let shelfID = UUID()

        repository.saveHome(Home(id: homeID, name: "Test Home", notes: ""))
        repository.saveCollection(
            Collection(
                id: collectionID,
                homeID: homeID,
                kind: .bells,
                title: "Test Collection",
                notes: ""
            )
        )

        let room = Location(
            id: roomID,
            homeID: homeID,
            parentLocationID: nil,
            kind: .room,
            name: "Room",
            notes: "",
            sortOrder: 0
        )
        let shelf = Location(
            id: shelfID,
            homeID: homeID,
            parentLocationID: roomID,
            kind: .shelf,
            name: "Shelf",
            notes: "",
            sortOrder: 1
        )
        repository.saveLocations([room, shelf], in: homeID)
        repository.saveItemRecord(makeItem(collectionID: collectionID, locationID: shelfID))
        repository.saveLocations([room], in: homeID)

        let archivedShelf = try #require(try collectionLocations(in: context)[shelfID])
        let archivedShelfID = try #require(archivedShelf.value(forKey: "id") as? UUID)
        let snapshot = CatalogSnapshot.load(from: context)
        #expect(snapshot.archivedCollectionLocationIDs == [archivedShelfID])

        let itemLocationIDs = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")).map {
            ($0.value(forKey: "collectionLocation") as? NSManagedObject)?.value(forKey: "id") as? UUID
        }
        let tree = snapshot.storageTree(for: collectionID, itemLocationIDs: itemLocationIDs)
        #expect(tree.nodes.map(\.location.name) == ["Room"])
        #expect(tree.nodes.first?.totalCount == 0)
        #expect(tree.archivedNodes.map(\.id) == [archivedShelfID])
        #expect(tree.archivedNodes.first?.totalCount == 1)
        #expect(tree.unassignedCount == 0)
    }

    private func makeItem(collectionID: UUID, locationID: UUID) -> ItemRecord {
        ItemRecord(
            id: UUID(),
            collectionID: collectionID,
            locationID: locationID,
            originPlaceID: nil,
            createdAt: .now,
            createdBy: "test",
            title: "Test item",
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
    }

    private func collectionLocations(in context: NSManagedObjectContext) throws -> [UUID: NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionLocationEntity")
        return Dictionary(
            try context.fetch(request).compactMap { entity in
                (entity.value(forKey: "sourceLocationID") as? UUID).map { ($0, entity) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func collectionLocationSourceIDs(in context: NSManagedObjectContext) throws -> Set<UUID> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionLocationEntity")
        return Set(try context.fetch(request).compactMap { $0.value(forKey: "sourceLocationID") as? UUID })
    }
}
