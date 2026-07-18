import CoreData
import Foundation

struct CatalogSnapshot {
    private(set) var homes: [Home] = []
    private(set) var locations: [Location] = []
    private(set) var collectionLocations: [Location] = []
    private(set) var collections: [Collection] = []
    private(set) var bells: [BellListItem] = []
    private(set) var bellRecords: [BellRecord] = []
    private(set) var places: [Place] = []
    private(set) var recordsByID: [UUID: BellRecord] = [:]
    private(set) var locationsByHomeID: [UUID: [Location]] = [:]
    private(set) var collectionLocationsByCollectionID: [UUID: [Location]] = [:]
    private(set) var collectionCountsByHomeID: [UUID: Int] = [:]
    private(set) var locationPathByID: [UUID: String] = [:]
    private(set) var collectionLocationPathByCollectionID: [UUID: [UUID: String]] = [:]

    private init() {}

    static func load(from context: NSManagedObjectContext) -> CatalogSnapshot {
        let homeEntities = fetchEntities(
            named: "HomeEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let locationEntities = fetchEntities(
            named: "LocationEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let collectionLocationEntities = fetchEntities(
            named: "CollectionLocationEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)]
        )
        let collectionEntities = fetchEntities(
            named: "CollectionEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]
        )
        let bellEntities = fetchEntities(
            named: "BellEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        )
        let placeEntities = fetchEntities(
            named: "PlaceEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)]
        )
        let records = bellEntities.map(bellRecord)

        var snapshot = CatalogSnapshot()
        snapshot.homes = homeEntities.map(home)
        snapshot.locations = locationEntities.map(storageLocation)
        snapshot.collectionLocations = collectionLocationEntities.map(collectionLocation)
        snapshot.collections = collectionEntities.map(collection)
        snapshot.bells = bellEntities.map(bellListItem)
        snapshot.bellRecords = records
        snapshot.places = placeEntities.map(place)
        snapshot.recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        snapshot.locationsByHomeID = Dictionary(grouping: locationEntities.compactMap(locationRow), by: \.0)
            .mapValues { rows in
                rows.map(\.1).sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        snapshot.collectionLocationsByCollectionID = Dictionary(
            grouping: collectionLocationEntities.compactMap(collectionLocationRow),
            by: \.0
        )
        .mapValues { rows in rows.map(\.1) }
        snapshot.collectionCountsByHomeID = Dictionary(
            collectionEntities.compactMap(collectionHomeID).map { ($0, 1) },
            uniquingKeysWith: +
        )
        snapshot.locationPathByID = Dictionary(
            uniqueKeysWithValues: locationEntities.map { (uuidValue($0, "id"), storageLocationPath(from: $0)) }
        )
        snapshot.collectionLocationPathByCollectionID = Dictionary(
            grouping: collectionLocationEntities.compactMap(collectionLocationPathRow),
            by: \.0
        )
        .mapValues { rows in Dictionary(rows.map(\.1), uniquingKeysWith: { first, _ in first }) }
        return snapshot
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

    private static func home(from entity: NSManagedObject) -> Home {
        Home(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            iconName: stringValue(entity, "iconName", default: "house.fill"),
            notes: stringValue(entity, "notes"),
            isShared: isSharedStoreEntity(entity)
        )
    }

    private static func isSharedStoreEntity(_ entity: NSManagedObject) -> Bool {
        entity.objectID.persistentStore?.url?.lastPathComponent == "Shared.sqlite"
    }

    private static func collection(from entity: NSManagedObject) -> Collection {
        Collection(
            id: uuidValue(entity, "id"),
            homeID: collectionHomeID(from: entity),
            kind: collectionKind(from: stringValue(entity, "kindRaw", default: CollectionKind.bells.rawValue)),
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            backgroundStyle: collectionBackgroundStyle(from: stringValue(entity, "backgroundStyleRaw", default: CollectionBackgroundStyle.amber.rawValue))
        )
    }

    private static func storageLocation(from entity: NSManagedObject) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: storageLocationHomeID(from: entity),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes")
        )
    }

    private static func collectionLocation(from entity: NSManagedObject) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: collectionLocationHomeID(from: entity),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes")
        )
    }

    private static func locationRow(from entity: NSManagedObject) -> (UUID, Location)? {
        guard let home = entity.value(forKey: "home") as? NSManagedObject else { return nil }
        let homeID = uuidValue(home, "id")

        return (
            homeID,
            Location(
                id: uuidValue(entity, "id"),
                homeID: homeID,
                parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
                kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
                name: stringValue(entity, "name"),
                notes: stringValue(entity, "notes")
            )
        )
    }

    private static func collectionLocationRow(from entity: NSManagedObject) -> (UUID, Location)? {
        guard let collectionID = collectionLocationCollectionID(from: entity) else { return nil }
        return (collectionID, collectionLocation(from: entity))
    }

    private static func collectionLocationPathRow(from entity: NSManagedObject) -> (UUID, (UUID, String))? {
        guard let collectionID = collectionLocationCollectionID(from: entity) else { return nil }
        return (collectionID, (uuidValue(entity, "id"), collectionLocationPath(from: entity)))
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

    private static func bellRecord(from entity: NSManagedObject) -> BellRecord {
        let id = uuidValue(entity, "id")
        let locationEntity = (entity.value(forKey: "collectionLocation") as? NSManagedObject)
            ?? entity.value(forKey: "location") as? NSManagedObject
        let originPlaceEntity = entity.value(forKey: "originPlace") as? NSManagedObject
        let tags = relatedObjects(entity, "tags")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { stringValue($0, "value") }

        return BellRecord(
            item: Item(
                id: id,
                collectionID: (entity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID(),
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
            storageLocation: locationEntity.map(locationForBellStorage),
            storagePath: locationEntity.map(storagePathForBellStorage) ?? "",
            mediaAssets: relatedObjects(entity, "mediaAssets")
                .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
                .map { mediaAsset(from: $0, itemID: id) },
            createdBy: stringValue(entity, "createdBy"),
            tags: tags
        )
    }

    private static func bellListItem(from entity: NSManagedObject) -> BellListItem {
        let record = bellRecord(from: entity)
        let locationEntity = (entity.value(forKey: "collectionLocation") as? NSManagedObject)
            ?? entity.value(forKey: "location") as? NSManagedObject
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

    private static func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    private static func storageLocationHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID()
    }

    private static func collectionLocationHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "collection") as? NSManagedObject).map(collectionHomeID) ?? UUID()
    }

    private static func collectionLocationCollectionID(from entity: NSManagedObject) -> UUID? {
        (entity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") }
    }

    private static func locationForBellStorage(from entity: NSManagedObject) -> Location {
        if entity.entity.name == "CollectionLocationEntity" {
            return collectionLocation(from: entity)
        }

        return storageLocation(from: entity)
    }

    private static func storagePathForBellStorage(from entity: NSManagedObject) -> String {
        if entity.entity.name == "CollectionLocationEntity" {
            return collectionLocationPath(from: entity)
        }

        return storageLocationPath(from: entity)
    }

    private static func storageLocationPath(from entity: NSManagedObject) -> String {
        locationPath(from: entity)
    }

    private static func collectionLocationPath(from entity: NSManagedObject) -> String {
        locationPath(from: entity)
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
        guard let value = entity.value(forKey: key) as? UUID else {
            fatalError("Missing UUID for \(entity.entity.name ?? "Unknown").\(key)")
        }
        return value
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

    private static func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private static func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
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
