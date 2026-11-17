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

    private func collectionLocationSourceIDs(in context: NSManagedObjectContext) throws -> Set<UUID> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionLocationEntity")
        return Set(try context.fetch(request).compactMap { $0.value(forKey: "sourceLocationID") as? UUID })
    }
}
