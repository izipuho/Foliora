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
        bells = bellEntities.map(Self.bellListItem)
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        locations = locationEntities.map(CoreDataDomainMapper.location)
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
        let record = CoreDataDomainMapper.bellRecord(from: entity)
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

    private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private static func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
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
