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
        locations = locationEntities.map {
            CoreDataDomainMapper.location(from: $0)
        }
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
        let coverPhoto = record.mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { $0.kind == .photo }

        return BellListItem(
            id: record.id,
            title: record.title,
            notes: record.notes,
            isFavorite: record.isFavorite,
            acquiredYear: record.acquiredYear,
            createdAt: record.createdAt,
            collectionID: record.item.collectionID,
            locationID: record.item.locationID,
            placeDisplayName: record.placeDisplayName,
            originLatitude: record.originPlace?.latitude,
            originLongitude: record.originPlace?.longitude,
            countryCode: record.originPlace?.countryCode ?? "",
            countryName: record.countryName,
            regionName: record.originPlace?.regionName ?? "",
            cityName: record.cityName,
            condition: record.condition,
            acquisitionMethod: record.acquisitionMethod,
            material: record.details.material,
            materialDisplayName: record.materialDisplayName,
            tagValues: record.tags,
            storagePath: record.storagePath,
            storageDisplayPath: record.storageDisplayPath,
            storageLocationName: record.storageLocationName,
            coverPhotoIdentifier: coverPhoto?.localIdentifier,
            coverPhotoThumbnailData: coverPhoto?.thumbnailData,
            coverPhotoOriginalData: nil,
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
}
