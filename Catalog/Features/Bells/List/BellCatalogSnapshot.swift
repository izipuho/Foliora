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
        let records = bellEntities.map(CoreDataDomainMapper.bellRecord)
        bells = records.map(Self.bellListItem)
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

    private static func bellListItem(from record: BellRecord) -> BellListItem {
        let storageComponents = storageComponents(from: record)
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

    private static func storageComponents(from record: BellRecord) -> [LocationKind: String] {
        guard let storageLocation = record.item.storageLocation else { return [:] }

        let pathComponents = record.item.storagePath
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let names = pathComponents.isEmpty ? [storageLocation.name] : pathComponents
        let kinds: [LocationKind] = [.floor, .room, .cabinet, .shelf]
        guard let leafIndex = kinds.firstIndex(of: storageLocation.kind) else {
            return [storageLocation.kind: storageLocation.name]
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
            notes: stringValue(entity, "notes")
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

    private static func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }
}

extension BellRecord {
    func moving(to location: Location?, path: String) -> BellRecord {
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
                storagePath: path,
                mediaAssets: mediaAssets
            ),
            details: details
        )
    }
}
