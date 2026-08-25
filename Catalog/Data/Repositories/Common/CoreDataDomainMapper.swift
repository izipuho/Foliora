import CoreData
import Foundation

/// Converts Core Data objects into domain models.
///
/// Centralizes all Core Data → domain mapping used by repositories,
/// snapshot loaders, and import/export.
enum CoreDataDomainMapper {
    static func itemRecord(from entity: NSManagedObject) -> ItemRecord {
        precondition(entity.entity.name == "ItemEntity", "CoreDataDomainMapper.itemRecord(from:) expects ItemEntity.")

        let id = uuidValue(entity, "id")
        let collectionEntity = entity.value(forKey: "collection") as? NSManagedObject
        let locationEntity = entity.value(forKey: "collectionLocation") as? NSManagedObject
        let originPlaceEntity = entity.value(forKey: "originPlace") as? NSManagedObject
        let tags = relatedObjects(entity, "tags")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { stringValue($0, "value") }
        let mediaAssets = relatedObjects(entity, "mediaAssets")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { mediaAsset(from: $0, itemID: id) }

        return ItemRecord(
            id: id,
            collectionID: collectionEntity.map { uuidValue($0, "id") } ?? UUID(),
            kind: collectionKind(from: stringValue(
                entity,
                "kind",
                default: collectionEntity.map { stringValue($0, "kind", default: CollectionKind.bells.rawValue) }
                    ?? CollectionKind.bells.rawValue
            )),
            locationID: locationEntity.map { uuidValue($0, "id") },
            originPlaceID: originPlaceEntity.map { uuidValue($0, "id") },
            createdAt: dateValue(entity, "createdAt"),
            createdBy: stringValue(entity, "createdBy"),
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            acquiredYear: optionalIntValue(entity, "acquisitionYear"),
            condition: itemCondition(from: stringValue(entity, "condition", default: ItemCondition.good.rawValue)),
            acquisitionMethod: acquisitionMethod(from: stringValue(entity, "acquisitionMethod", default: AcquisitionMethod.bought.rawValue)),
            isFavorite: entity.value(forKey: "isFavorite") as? Bool ?? false,
            tags: tags,
            originPlace: originPlaceEntity.map(place),
            storageLocation: locationEntity.map { location(from: $0) },
            storagePath: locationEntity.map(storagePath),
            mediaAssets: mediaAssets
        )
    }

    static func place(from entity: NSManagedObject) -> Place {
        Place(
            id: uuidValue(entity, "id"),
            displayName: stringValue(entity, "displayName"),
            countryCode: stringValue(entity, "countryCode"),
            countryName: stringValue(entity, "countryName"),
            regionName: entity.value(forKey: "regionName") as? String,
            cityName: entity.value(forKey: "cityName") as? String,
            latitude: doubleValue(entity, "latitude"),
            longitude: doubleValue(entity, "longitude")
        )
    }

    static func person(from entity: NSManagedObject) -> Person {
        precondition(entity.entity.name == "PersonEntity", "CoreDataDomainMapper.person(from:) expects PersonEntity.")

        let birthPlaceEntity = entity.value(forKey: "birthPlace") as? NSManagedObject
        let deathPlaceEntity = entity.value(forKey: "deathPlace") as? NSManagedObject

        return Person(
            name: stringValue(entity, "name"),
            birthYear: optionalIntValue(entity, "birthYear"),
            deathYear: optionalIntValue(entity, "deathYear"),
            biography: entity.value(forKey: "biography") as? String,
            birthPlace: birthPlaceEntity.map(place),
            deathPlace: deathPlaceEntity.map(place)
        )
    }

    static func location(from entity: NSManagedObject, sortOrder: Int? = nil) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: locationHomeID(from: entity),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kind", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes"),
            sortOrder: sortOrder
        )
    }

    static func mediaAsset(from entity: NSManagedObject, itemID: UUID) -> MediaAsset {
        MediaAsset(
            id: uuidValue(entity, "id"),
            itemID: itemID,
            kind: mediaKind(from: stringValue(entity, "kind", default: MediaKind.photo.rawValue)),
            localIdentifier: stringValue(entity, "localIdentifier"),
            displayName: entity.value(forKey: "displayName") as? String,
            sortOrder: intValue(entity, "sortOrder"),
            fileName: entity.value(forKey: "fileName") as? String,
            mimeType: entity.value(forKey: "mimeType") as? String,
            byteSize: optionalIntValue(entity, "byteSize"),
            checksum: entity.value(forKey: "checksum") as? String,
            width: optionalIntValue(entity, "width"),
            height: optionalIntValue(entity, "height"),
            duration: doubleValue(entity, "duration"),
            metadataJSON: entity.value(forKey: "metadataJSON") as? String,
            originalData: entity.value(forKey: "originalData") as? Data
        )
    }

    static func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    static func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    static func intValue(_ entity: NSManagedObject, _ key: String) -> Int {
        optionalIntValue(entity, key) ?? 0
    }

    static func optionalIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        if let value = entity.value(forKey: key) as? Int {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.intValue
    }

    static func dateValue(_ entity: NSManagedObject, _ key: String) -> Date {
        entity.value(forKey: key) as? Date ?? Date()
    }

    static func doubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    private static func locationHomeID(from entity: NSManagedObject) -> UUID {
        if entity.entity.name == "LocationEntity",
           let home = entity.value(forKey: "home") as? NSManagedObject {
            return uuidValue(home, "id")
        }

        if entity.entity.name == "CollectionLocationEntity",
           let collection = entity.value(forKey: "collection") as? NSManagedObject {
            return collectionHomeID(from: collection)
        }

        return UUID()
    }

    private static func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }

    private static func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private static func itemCondition(from rawValue: String) -> ItemCondition {
        ItemCondition(rawValue: rawValue) ?? .good
    }

    private static func acquisitionMethod(from rawValue: String) -> AcquisitionMethod {
        AcquisitionMethod(rawValue: rawValue) ?? .other
    }

    private static func mediaKind(from rawValue: String) -> MediaKind {
        MediaKind(rawValue: rawValue) ?? .photo
    }

    private static func storagePath(from entity: NSManagedObject) -> StoragePath {
        var components: [StoragePath.Component] = []
        var current: NSManagedObject? = entity

        while let location = current {
            components.insert(
                StoragePath.Component(
                    kind: locationKind(from: stringValue(location, "kind", default: LocationKind.room.rawValue)),
                    name: stringValue(location, "name")
                ),
                at: 0
            )
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return StoragePath(components: components)
    }
}
