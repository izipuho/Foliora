import CoreData
import Foundation

/// Represents bell catalog snapshot data and behavior.
struct BellCatalogSnapshot {
    var bells: [BellListItem] = []
    var locations: [Location] = []
    var locationPathByID: [UUID: String] = [:]

    init() {}

    init(context: NSManagedObjectContext, collectionID: UUID?) {
        let bellEntities = Self.fetchEntities(
            named: "BellEntity",
            in: context,
            predicate: collectionID.map { NSPredicate(format: "item.collection.id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "item.createdAt", ascending: false)]
        )
        let collectionEntities = Self.fetchEntities(
            named: "CollectionEntity",
            in: context,
            predicate: collectionID.map { NSPredicate(format: "id == %@", $0 as NSUUID) }
        )
        var locationEntities = collectionID.map {
            Self.fetchEntities(
                named: "CollectionLocationEntity",
                in: context,
                predicate: NSPredicate(format: "collection.id == %@", $0 as NSUUID),
                sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)]
            )
        } ?? []
        if collectionID == nil || locationEntities.isEmpty {
            let homeID = collectionEntities.first.map(Self.collectionHomeID)
            locationEntities = Self.fetchEntities(
                named: "LocationEntity",
                in: context,
                predicate: homeID.map { NSPredicate(format: "home.id == %@", $0 as NSUUID) },
                sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
            )
        }
        bells = bellEntities.map(Self.bellListItem)
        locations = locationEntities.map(Self.location)
        locationPathByID = Dictionary(uniqueKeysWithValues: locationEntities.map { (Self.uuidValue($0, "id"), Self.locationPath(from: $0)) })
    }

    private static func fetchEntities(
        named entityName: String,
        in context: NSManagedObjectContext,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = []
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return (try? context.fetch(request)) ?? []
    }

    private static func bellListItem(from entity: NSManagedObject) -> BellListItem {
        guard let itemEntity = entity.value(forKey: "item") as? NSManagedObject else {
            preconditionFailure("BellEntity is missing its migrated ItemEntity relationship.")
        }

        let locationEntity = itemEntity.value(forKey: "collectionLocation") as? NSManagedObject
        let originPlaceEntity = itemEntity.value(forKey: "originPlace") as? NSManagedObject
        let material = bellMaterial(from: stringValue(entity, "materialRaw", default: BellMaterial.unknown.rawValue))
        let customMaterialName = entity.value(forKey: "customMaterialName") as? String
        let storageLocationName = locationEntity.map { stringValue($0, "name") } ?? String(localized: "common.unassigned")
        let storageDisplayPath = locationEntity.map(locationPath) ?? storageLocationName
        let storageComponents = locationEntity.map(storageComponents) ?? [:]
        let tags = relatedObjects(itemEntity, "tags")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { stringValue($0, "value") }
        let coverPhoto = relatedObjects(itemEntity, "mediaAssets")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .first { stringValue($0, "kindRaw") == MediaKind.photo.rawValue }
        let coverPhotoIdentifier = coverPhoto.flatMap {
            let identifier = stringValue($0, "localIdentifier")
            return identifier.isEmpty ? nil : identifier
        }

        return BellListItem(
            id: uuidValue(itemEntity, "id"),
            title: stringValue(itemEntity, "title"),
            notes: stringValue(itemEntity, "notes"),
            isFavorite: itemEntity.value(forKey: "isFavorite") as? Bool ?? false,
            acquiredYear: optionalIntValue(itemEntity, "acquisitionYear"),
            createdAt: dateValue(itemEntity, "createdAt"),
            collectionID: (itemEntity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") },
            locationID: locationEntity.map { uuidValue($0, "id") },
            placeDisplayName: originPlaceEntity.map { stringValue($0, "displayName") } ?? String(localized: "common.unknown_origin"),
            originLatitude: originPlaceEntity.flatMap { doubleValue($0, "latitude") },
            originLongitude: originPlaceEntity.flatMap { doubleValue($0, "longitude") },
            countryCode: originPlaceEntity.map { stringValue($0, "countryCode") } ?? "",
            countryName: originPlaceEntity.map { stringValue($0, "countryName") } ?? "",
            regionName: originPlaceEntity.flatMap { $0.value(forKey: "regionName") as? String } ?? "",
            cityName: originPlaceEntity.flatMap { $0.value(forKey: "cityName") as? String } ?? "",
            condition: itemCondition(from: stringValue(itemEntity, "condition", default: ItemCondition.good.rawValue)),
            acquisitionMethod: acquisitionMethod(from: stringValue(itemEntity, "acquisitionMethod", default: AcquisitionMethod.bought.rawValue)),
            material: material,
            materialDisplayName: materialDisplayName(material: material, customMaterialName: customMaterialName),
            tagValues: tags,
            storageFloor: storageComponents[.floor] ?? "",
            storageRoom: storageComponents[.room] ?? "",
            storageCabinet: storageComponents[.cabinet] ?? "",
            storageShelf: storageComponents[.shelf] ?? "",
            storageDisplayPath: storageDisplayPath,
            storageLocationName: storageLocationName,
            coverPhotoIdentifier: coverPhotoIdentifier,
            coverPhotoThumbnailData: coverPhoto?.value(forKey: "thumbnailData") as? Data,
            coverPhotoOriginalData: nil,
            hasOrigin: originPlaceEntity != nil,
            hasStorage: locationEntity != nil
        )
    }

    private static func storageComponents(from entity: NSManagedObject) -> [LocationKind: String] {
        let storageLocationName = stringValue(entity, "name")
        let storageLocationKind = locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue))
        let pathComponents = locationPath(from: entity)
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let names = pathComponents.isEmpty ? [storageLocationName] : pathComponents
        let kinds: [LocationKind] = [.floor, .room, .cabinet, .shelf]
        guard let leafIndex = kinds.firstIndex(of: storageLocationKind) else {
            return [storageLocationKind: storageLocationName]
        }

        let startIndex = max(0, leafIndex - names.count + 1)
        let pathKinds = kinds[startIndex...leafIndex]
        return Dictionary(uniqueKeysWithValues: zip(pathKinds, names))
    }

    private static func location(from entity: NSManagedObject) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: locationHomeID(from: entity),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes"),
            sortOrder: nil
        )
    }

    private static func locationPath(from entity: NSManagedObject) -> String {
        var parts: [String] = []
        var current: NSManagedObject? = entity

        while let location = current {
            parts.insert(stringValue(location, "name"), at: 0)
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return parts.joined(separator: " / ")
    }

    private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
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

    private static func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    private static func intValue(_ entity: NSManagedObject, _ key: String) -> Int {
        optionalIntValue(entity, key) ?? 0
    }

    private static func optionalIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        if let value = entity.value(forKey: key) as? Int {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.intValue
    }

    private static func dateValue(_ entity: NSManagedObject, _ key: String) -> Date {
        entity.value(forKey: key) as? Date ?? Date()
    }

    private static func doubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }

    private static func itemCondition(from rawValue: String) -> ItemCondition {
        ItemCondition(rawValue: rawValue) ?? .good
    }

    private static func acquisitionMethod(from rawValue: String) -> AcquisitionMethod {
        AcquisitionMethod(rawValue: rawValue) ?? .other
    }

    private static func bellMaterial(from rawValue: String) -> BellMaterial {
        BellMaterial(rawValue: rawValue) ?? .unknown
    }

    private static func materialDisplayName(material: BellMaterial, customMaterialName: String?) -> String {
        if material == .other, let customMaterialName, !customMaterialName.isEmpty {
            return customMaterialName
        }

        return material.displayName
    }

    private static func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }
}

extension BellRecord {
    func moving(
        to location: Location?,
        storagePath: StoragePath?
    ) -> BellRecord {
        BellRecord(
            item: ItemRecord(
                id: item.id,
                collectionID: item.collectionID,
                locationID: location?.id,
                originPlaceID: item.originPlaceID,
                createdAt: item.createdAt,
                createdBy: createdBy,
                title: item.title,
                notes: item.notes,
                acquiredYear: item.acquiredYear,
                condition: item.condition,
                acquisitionMethod: item.acquisitionMethod,
                isFavorite: isFavorite,
                tags: tags,
                originPlace: originPlace,
                storageLocation: location,
                storagePath: storagePath,
                mediaAssets: mediaAssets
            ),
            details: details
        )
    }
}
