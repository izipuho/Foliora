//
//  PreviewData.swift
//  Foliora
//
//  Created by Ivan Zipuho on 01.08.2026.
//

import CoreData
import Foundation

@MainActor
enum PreviewData {
    static func populateMinimal(context: NSManagedObjectContext) {
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )

        let homeID = UUID()
        let locationID = UUID()
        let collectionID = UUID()
        let itemID = UUID()

        let home = Home(
            id: homeID,
            name: "Home",
            notes: ""
        )
        let location = Location(
            id: locationID,
            homeID: homeID,
            parentLocationID: nil,
            kind: .shelf,
            name: "Shelf",
            notes: "",
            sortOrder: nil
        )
        let collection = Collection(
            id: collectionID,
            homeID: homeID,
            kind: .bells,
            title: "Bells",
            notes: ""
        )
        let item = ItemRecord(
            id: itemID,
            collectionID: collectionID,
            locationID: locationID,
            originPlaceID: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            createdBy: "",
            title: "Bell",
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .other,
            isFavorite: false,
            tags: [],
            originPlace: nil,
            storageLocation: location,
            storagePath: location.name,
            mediaAssets: []
        )
        let bell = BellRecord(
            item: item,
            details: BellDetails(
                itemID: itemID,
                material: .unknown,
                customMaterialName: nil
            )
        )

        repository.saveHome(home)
        repository.saveLocations([location], in: homeID)
        repository.saveCollection(collection)
        repository.saveBellRecord(bell)
    }
}
