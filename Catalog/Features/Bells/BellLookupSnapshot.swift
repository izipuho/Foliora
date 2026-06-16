import CoreData
import Foundation

struct BellLookupSnapshot {
    var bells: [BellRecord] = []
    var locations: [Location] = []
    var collections: [Collection] = []
    var homes: [Home] = []
    var places: [Place] = []
    var locationPathByID: [UUID: String] = [:]

    init() {}
}

protocol BellLookupSnapshotLoading {
    func loadSnapshot(collectionID: UUID?, homeID: UUID?) -> BellLookupSnapshot
}

struct CoreDataBellLookupSnapshotLoader: BellLookupSnapshotLoading {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadSnapshot(collectionID: UUID? = nil, homeID: UUID? = nil) -> BellLookupSnapshot {
        let bellEntities = fetchEntities(
            named: "BellEntity",
            predicate: collectionID.map { NSPredicate(format: "collection.id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        )
        let collectionEntities = fetchEntities(
            named: "CollectionEntity",
            predicate: collectionID.map { NSPredicate(format: "id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]
        )
        var locationEntities = collectionID.map {
            fetchEntities(
                named: "CollectionLocationEntity",
                predicate: NSPredicate(format: "collection.id == %@", $0 as NSUUID),
                sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)]
            )
        } ?? []
        if collectionID == nil || locationEntities.isEmpty {
            let resolvedHomeID = collectionEntities.first.map(collectionHomeID) ?? homeID
            locationEntities = fetchEntities(
                named: "LocationEntity",
                predicate: resolvedHomeID.map { NSPredicate(format: "home.id == %@", $0 as NSUUID) },
                sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
            )
        }
        let homeEntities = fetchEntities(
            named: "HomeEntity",
            predicate: homeID.map { NSPredicate(format: "id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let placeEntities = fetchEntities(
            named: "PlaceEntity",
            sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)]
        )

        let bells = bellEntities.map(bellRecord)
        let locations = locationEntities.map(location)

        var snapshot = BellLookupSnapshot()
        snapshot.bells = bells
        snapshot.locations = locations
        snapshot.collections = collectionEntities.map(collection)
        snapshot.homes = homeEntities.map(home)
        snapshot.places = placeEntities.map(place)
        snapshot.locationPathByID = Dictionary(
            uniqueKeysWithValues: locationEntities.map { (uuidValue($0, "id"), locationPath(from: $0)) }
        )
        return snapshot
    }

    private func fetchEntities(
        named entityName: String,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = []
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return (try? context.fetch(request)) ?? []
    }

    private func home(from entity: NSManagedObject) -> Home {
        Home(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            iconName: stringValue(entity, "iconName", default: "house.fill"),
            notes: stringValue(entity, "notes")
        )
    }

    private func collection(from entity: NSManagedObject) -> Collection {
        Collection(
            id: uuidValue(entity, "id"),
            homeID: collectionHomeID(from: entity),
            kind: collectionKind(from: stringValue(entity, "kindRaw", default: CollectionKind.bells.rawValue)),
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            backgroundStyle: collectionBackgroundStyle(from: stringValue(entity, "backgroundStyleRaw", default: CollectionBackgroundStyle.amber.rawValue))
        )
    }

    private func bellRecord(from entity: NSManagedObject) -> BellRecord {
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
            storageLocation: locationEntity.map(location),
            storagePath: locationEntity.map(locationPath) ?? "",
            mediaAssets: relatedObjects(entity, "mediaAssets")
                .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
                .map { mediaAsset(from: $0, itemID: id) },
            createdBy: stringValue(entity, "createdBy"),
            tags: tags
        )
    }

    private func location(from entity: NSManagedObject) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: locationHomeID(from: entity),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes")
        )
    }

    private func place(from entity: NSManagedObject) -> Place {
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

    private func mediaAsset(from entity: NSManagedObject, itemID: UUID) -> MediaAsset {
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

    private func locationPath(from entity: NSManagedObject) -> String {
        var parts: [String] = []
        var current: NSManagedObject? = entity

        while let location = current {
            parts.insert(stringValue(location, "name"), at: 0)
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return parts.joined(separator: " / ")
    }

    private func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    private func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    private func locationHomeID(from entity: NSManagedObject) -> UUID {
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

    private func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    private func intValue(_ entity: NSManagedObject, _ key: String) -> Int {
        optionalIntValue(entity, key) ?? 0
    }

    private func optionalIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        if let value = entity.value(forKey: key) as? Int {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.intValue
    }

    private func dateValue(_ entity: NSManagedObject, _ key: String) -> Date {
        entity.value(forKey: key) as? Date ?? Date()
    }

    private func optionalDoubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }

    private func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
    }

    private func itemCondition(from rawValue: String) -> ItemCondition {
        ItemCondition(rawValue: rawValue) ?? .good
    }

    private func acquisitionMethod(from rawValue: String) -> AcquisitionMethod {
        AcquisitionMethod(rawValue: rawValue) ?? .bought
    }

    private func bellMaterial(from rawValue: String) -> BellMaterial {
        BellMaterial(rawValue: rawValue) ?? .unknown
    }

    private func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }

    private func mediaKind(from rawValue: String) -> MediaKind {
        MediaKind(rawValue: rawValue) ?? .photo
    }
}
