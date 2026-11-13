import CoreData
import Foundation
import OSLog

/// Converts Core Data objects into domain models.
///
/// Centralizes all Core Data → domain mapping used by repositories,
/// snapshot loaders, and import/export.
enum CoreDataDomainMapper {
    /// Reports references that CloudKit has not linked yet.
    ///
    /// CloudKit imports records in batches without transactions, so a publisher, person,
    /// or series can arrive before the record it points to. Such an object is skipped until
    /// a later import links it and triggers another snapshot reload.
    nonisolated private static let unlinkedReferenceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Catalog",
        category: "CoreDataDomainMapper"
    )

    static func itemRecord(from entity: NSManagedObject, includesMediaData: Bool = true) -> ItemRecord {
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
            .map { mediaAsset(from: $0, itemID: id, includesMediaData: includesMediaData) }

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
        precondition(entity.entity.name == "PlaceEntity", "CoreDataDomainMapper.place(from:) expects PlaceEntity.")

        let id = uuidValue(entity, "id")
        let collectionID = (entity.value(forKey: "collection") as? NSManagedObject).map {
            uuidValue($0, "id")
        }

        return Place(
            id: id,
            canonicalID: entity.value(forKey: "canonicalID") as? UUID ?? id,
            collectionID: collectionID,
            displayName: stringValue(entity, "displayName"),
            countryCode: stringValue(entity, "countryCode"),
            countryName: stringValue(entity, "countryName"),
            regionName: entity.value(forKey: "regionName") as? String,
            cityName: entity.value(forKey: "cityName") as? String,
            latitude: doubleValue(entity, "latitude"),
            longitude: doubleValue(entity, "longitude")
        )
    }

    /// Maps a person, or returns `nil` while CloudKit has not linked it to its collection.
    static func person(from entity: NSManagedObject, includesMediaData: Bool = true) -> Person? {
        precondition(entity.entity.name == "PersonEntity", "CoreDataDomainMapper.person(from:) expects PersonEntity.")

        let id = uuidValue(entity, "id")
        guard let collectionEntity = entity.value(forKey: "collection") as? NSManagedObject else {
            logUnlinkedReference(entity, missing: "collection")
            return nil
        }

        let photos = relatedObjects(entity, "photos")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { mediaAsset(from: $0, includesMediaData: includesMediaData) }

        return Person(
            id: id,
            canonicalID: entity.value(forKey: "canonicalID") as? UUID ?? id,
            collectionID: uuidValue(collectionEntity, "id"),
            givenName: stringValue(entity, "givenName"),
            familyName: optionalStringValue(entity, "familyName"),
            middleName: optionalStringValue(entity, "middleName"),
            birthYear: optionalIntValue(entity, "birthYear"),
            deathYear: optionalIntValue(entity, "deathYear"),
            biography: entity.value(forKey: "biography") as? String,
            birthPlace: optionalStringValue(entity, "birthPlace"),
            deathPlace: optionalStringValue(entity, "deathPlace"),
            photos: photos
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

    /// Maps a media asset entity.
    ///
    /// - Parameter includesMediaData: When `false`, `originalData` is left `nil` and the stored bytes are
    ///   never faulted in; consumers load them by asset ID. Snapshot list models use this mode.
    static func mediaAsset(
        from entity: NSManagedObject,
        itemID: UUID? = nil,
        includesMediaData: Bool = true
    ) -> MediaAsset {
        MediaAsset(
            id: uuidValue(entity, "id"),
            itemID: itemID,
            kind: mediaKind(from: stringValue(entity, "kind", default: MediaKind.photo.rawValue)),
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
            originalData: includesMediaData ? entity.value(forKey: "originalData") as? Data : nil
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

    static func optionalStringValue(_ entity: NSManagedObject, _ key: String) -> String? {
        guard let value = entity.value(forKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    /// Logs an object skipped because a relationship CloudKit has not imported yet is missing.
    nonisolated static func logUnlinkedReference(_ entity: NSManagedObject, missing relationship: String) {
        let entityName = entity.entity.name ?? "unknown"
        let id = (entity.value(forKey: "id") as? UUID)?.uuidString ?? "unknown"
        unlinkedReferenceLogger.notice(
            "Skipping \(entityName, privacy: .public) \(id, privacy: .public): missing \(relationship, privacy: .public) relationship."
        )
    }
}
