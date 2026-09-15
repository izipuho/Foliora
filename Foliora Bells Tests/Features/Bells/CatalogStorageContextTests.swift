import CoreData
import Foundation
import Testing
@testable import Foliora_Bells

@MainActor
struct CatalogStorageContextTests {
    @Test
    func storagePathBuildsCollectionLocationHierarchyInOrder() throws {
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
        let shelfID = UUID()

        repository.saveHome(
            Home(
                id: homeID,
                name: "Test Home",
                notes: ""
            )
        )
        repository.saveCollection(
            Collection(
                id: collectionID,
                homeID: homeID,
                kind: .bells,
                title: "Test Collection",
                notes: ""
            )
        )
        repository.saveLocations(
            [
                Location(
                    id: roomID,
                    homeID: homeID,
                    parentLocationID: nil,
                    kind: .room,
                    name: "Room",
                    notes: "",
                    sortOrder: 0
                ),
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
                    id: shelfID,
                    homeID: homeID,
                    parentLocationID: cabinetID,
                    kind: .shelf,
                    name: "Shelf",
                    notes: "",
                    sortOrder: 2
                )
            ],
            in: homeID
        )

        let snapshot = CatalogSnapshot.load(from: context)
        let collection = try #require(snapshot.collectionSummary(id: collectionID))
        let storageContext = CatalogStorageContext(
            snapshot: snapshot,
            collection: collection
        )
        let shelf = try #require(storageContext.location(for: shelfID))
        let storagePath = storageContext.storagePath(for: shelf)

        #expect(storageContext.locationPathByID[shelfID] == "Room / Cabinet / Shelf")
        #expect(storagePath.components.map(\.kind) == [.room, .cabinet, .shelf])
        #expect(storagePath.displayPath == "Room / Cabinet / Shelf")
    }
}
