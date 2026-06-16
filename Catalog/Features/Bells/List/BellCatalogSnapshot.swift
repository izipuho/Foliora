import CoreData
import Foundation

struct BellCatalogSnapshot {
    var bells: [BellListItem] = []
    var recordsByID: [UUID: BellRecord] = [:]
    var locations: [Location] = []
    var locationPathByID: [UUID: String] = [:]

    init() {}

    init(context: NSManagedObjectContext, collectionID: UUID?) {
        let bellEntities = Self.fetchEntities(
            named: "BellEntity",
            in: context,
            predicate: collectionID.map { NSPredicate(format: "collection.id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        )
        let locationEntities = Self.fetchEntities(
            named: "LocationEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let records = bellEntities.map(Self.bellRecord)
        bells = bellEntities.map(Self.bellListItem)
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
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

    private static func bellRecord(from entity: NSManagedObject) -> BellRecord {
        let id = uuidValue(entity, "id")
        let locationEntity = entity.value(forKey: "location") as? NSManagedObject
        let originPlaceEntity = entity.value(forKey: "originPlace") as? NSManagedObject
        let collectionID = (entity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID()
        let tags = relatedObjects(entity, "tags")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { stringValue($0, "value") }

        return BellRecord(
            item: Item(
                id: id,
                collectionID: collectionID,
                locationID: locationEntity.map { uuidValue($0, "id") },
                createdAt: dateValue(entity, "createdAt"),
                title: stringValue(entity, "title"),
                notes: stringValue(entity, "notes"),
                acquiredYear: optionalIntValue(entity, "acquiredYear"),
                condition: itemCondition(from: stringValue(entity, "conditionRaw", default: ItemCondition.good.rawValue)),
                acquisitionMethod: acquisitionMethod(from: stringValue(entity, "acquisitionMethodRaw", default: AcquisitionMethod.bought.rawValue))
            ),
            details: BellDetails(
                itemID: id,
                originPlaceID: originPlaceEntity.map { uuidValue($0, "id") },
                material: bellMaterial(from: stringValue(entity, "materialRaw", default: BellMaterial.unknown.rawValue)),
                customMaterialName: entity.value(forKey: "customMaterialName") as? String
            ),
            originPlace: originPlaceEntity.map(place),
            storageLocation: locationEntity.map(location),
            storagePath: locationEntity.map(locationPath) ?? "",
            mediaAssets: relatedObjects(entity, "mediaAssets")
                .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
                .map { mediaAsset(from: $0, itemID: id) },
            createdBy: stringValue(entity, "createdBy"),
            tags: tags
        )
    }

    private static func bellListItem(from entity: NSManagedObject) -> BellListItem {
        let record = bellRecord(from: entity)
        let locationEntity = entity.value(forKey: "location") as? NSManagedObject
        let storageComponents = locationEntity.map(storageComponents) ?? [:]
        let coverPhoto = record.mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { $0.kind == .photo }

        return BellListItem(
            id: record.id,
            title: record.title,
            notes: record.notes,
            acquiredYear: record.acquiredYear,
            createdAt: record.createdAt,
            collectionID: record.item.collectionID,
            locationID: record.item.locationID,
            placeDisplayName: record.placeDisplayName,
            countryCode: record.originPlace?.countryCode ?? "",
            countryName: record.countryName,
            regionName: record.originPlace?.regionName ?? "",
            cityName: record.cityName,
            condition: record.condition,
            acquisitionMethod: record.acquisitionMethod,
            material: record.details.material,
            materialDisplayName: record.materialDisplayName,
            tagValues: record.tags,
            storageFloor: storageComponents[.floor] ?? "",
            storageRoom: storageComponents[.room] ?? "",
            storageCabinet: storageComponents[.cabinet] ?? "",
            storageShelf: storageComponents[.shelf] ?? "",
            coverPhotoIdentifier: coverPhoto?.localIdentifier,
            coverPhotoThumbnailData: coverPhoto?.thumbnailData,
            coverPhotoOriginalData: coverPhoto?.originalData,
            hasOrigin: record.originPlace != nil,
            hasStorage: record.item.locationID != nil
        )
    }

    private static func location(from entity: NSManagedObject) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID(),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes")
        )
    }

    private static func place(from entity: NSManagedObject) -> Place {
        Place(
            id: uuidValue(entity, "id"),
            displayName: stringValue(entity, "displayName"),
            countryCode: stringValue(entity, "countryCode"),
            countryName: stringValue(entity, "countryName"),
            regionName: entity.value(forKey: "regionName") as? String,
            cityName: entity.value(forKey: "cityName") as? String,
            latitude: optionalDoubleValue(entity, "latitude"),
            longitude: optionalDoubleValue(entity, "longitude")
        )
    }

    private static func mediaAsset(from entity: NSManagedObject, itemID: UUID) -> MediaAsset {
        MediaAsset(
            id: uuidValue(entity, "id"),
            itemID: itemID,
            kind: mediaKind(from: stringValue(entity, "kindRaw", default: MediaKind.photo.rawValue)),
            localIdentifier: stringValue(entity, "localIdentifier"),
            displayName: entity.value(forKey: "displayName") as? String,
            sortOrder: intValue(entity, "sortOrder"),
            fileName: entity.value(forKey: "fileName") as? String,
            mimeType: entity.value(forKey: "mimeType") as? String,
            byteSize: optionalIntValue(entity, "byteSize"),
            checksum: entity.value(forKey: "checksum") as? String,
            width: optionalIntValue(entity, "width"),
            height: optionalIntValue(entity, "height"),
            duration: optionalDoubleValue(entity, "duration"),
            metadataJSON: entity.value(forKey: "metadataJSON") as? String,
            thumbnailData: entity.value(forKey: "thumbnailData") as? Data,
            originalData: entity.value(forKey: "originalData") as? Data
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

    private static func storageComponents(from entity: NSManagedObject) -> [LocationKind: String] {
        var components: [LocationKind: String] = [:]
        var current: NSManagedObject? = entity

        while let location = current {
            let kind = locationKind(from: stringValue(location, "kindRaw", default: LocationKind.room.rawValue))
            let name = stringValue(location, "name").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, components[kind] == nil {
                components[kind] = name
            }
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return components
    }

    private static func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
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

    private static func optionalDoubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func itemCondition(from rawValue: String) -> ItemCondition {
        ItemCondition(rawValue: rawValue) ?? .good
    }

    private static func acquisitionMethod(from rawValue: String) -> AcquisitionMethod {
        AcquisitionMethod(rawValue: rawValue) ?? .bought
    }

    private static func bellMaterial(from rawValue: String) -> BellMaterial {
        BellMaterial(rawValue: rawValue) ?? .unknown
    }

    private static func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }

    private static func mediaKind(from rawValue: String) -> MediaKind {
        MediaKind(rawValue: rawValue) ?? .photo
    }
}

extension BellRecord {
    func moving(to location: Location?, path: String) -> BellRecord {
        BellRecord(
            item: Item(
                id: item.id,
                collectionID: item.collectionID,
                locationID: location?.id,
                createdAt: item.createdAt,
                title: item.title,
                notes: item.notes,
                acquiredYear: item.acquiredYear,
                condition: item.condition,
                acquisitionMethod: item.acquisitionMethod
            ),
            details: details,
            originPlace: originPlace,
            storageLocation: location,
            storagePath: path,
            mediaAssets: mediaAssets,
            createdBy: createdBy,
            tags: tags
        )
    }
}
