import CoreData
import Foundation
import Testing
@testable import Foliora_Books

@MainActor
struct CoreDataPlaceRepositoryTests {
    @Test
    func materializesSameLogicalPlaceWithSeparatePhysicalIdentityPerCollection() throws {
        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )

        let homeID = UUID()
        let firstCollectionID = UUID()
        let secondCollectionID = UUID()
        repository.saveCollection(
            Collection(
                id: firstCollectionID,
                homeID: homeID,
                kind: .bells,
                title: "First",
                notes: ""
            )
        )
        repository.saveCollection(
            Collection(
                id: secondCollectionID,
                homeID: homeID,
                kind: .bells,
                title: "Second",
                notes: ""
            )
        )

        let canonicalID = UUID()
        let firstPlace = Place(
            id: UUID(),
            canonicalID: canonicalID,
            collectionID: firstCollectionID,
            displayName: "Paris, France",
            countryCode: "FR",
            countryName: "France",
            regionName: "Île-de-France",
            cityName: "Paris",
            latitude: 48.8566,
            longitude: 2.3522
        )
        repository.saveItemRecord(
            makeItem(collectionID: firstCollectionID, place: firstPlace)
        )

        let mapKitPlace = Place(
            id: UUID(),
            collectionID: secondCollectionID,
            displayName: "Paris, France",
            countryCode: "FR",
            countryName: "France",
            regionName: "Île-de-France",
            cityName: "Paris",
            latitude: 48.8566,
            longitude: 2.3522
        )
        #expect(mapKitPlace.canonicalID == mapKitPlace.id)
        #expect(mapKitPlace.canonicalID != canonicalID)

        repository.saveItemRecord(
            makeItem(collectionID: secondCollectionID, place: mapKitPlace)
        )

        let request = NSFetchRequest<NSManagedObject>(entityName: "PlaceEntity")
        let persistedPlaces = try context.fetch(request)
        #expect(persistedPlaces.count == 2)

        let placesByCollectionID = Dictionary(
            uniqueKeysWithValues: persistedPlaces.compactMap { entity -> (UUID, NSManagedObject)? in
                guard
                    let collection = entity.value(forKey: "collection") as? NSManagedObject,
                    let collectionID = collection.value(forKey: "id") as? UUID
                else {
                    return nil
                }
                return (collectionID, entity)
            }
        )

        let firstPersistedPlace = try #require(placesByCollectionID[firstCollectionID])
        let secondPersistedPlace = try #require(placesByCollectionID[secondCollectionID])
        let firstPhysicalID = try #require(firstPersistedPlace.value(forKey: "id") as? UUID)
        let secondPhysicalID = try #require(secondPersistedPlace.value(forKey: "id") as? UUID)
        let firstCanonicalID = try #require(firstPersistedPlace.value(forKey: "canonicalID") as? UUID)
        let secondCanonicalID = try #require(secondPersistedPlace.value(forKey: "canonicalID") as? UUID)

        #expect(firstPhysicalID != secondPhysicalID)
        #expect(firstCanonicalID == canonicalID)
        #expect(secondCanonicalID == canonicalID)
        #expect(firstCanonicalID == secondCanonicalID)
    }

    private func makeItem(collectionID: UUID, place: Place) -> ItemRecord {
        ItemRecord(
            id: UUID(),
            collectionID: collectionID,
            locationID: nil,
            originPlaceID: place.id,
            createdAt: .now,
            createdBy: "test",
            title: "Test item",
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .other,
            isFavorite: false,
            tags: [],
            originPlace: place,
            storageLocation: nil,
            storagePath: nil,
            mediaAssets: []
        )
    }
}
