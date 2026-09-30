import CoreData
import Foundation

/// Bell records held by `CatalogSnapshot`, mapped once per load.
struct CatalogRecords {
    let bellRecords: [BellRecord]
    let bells: [BellCatalogItem]
    let recordsByID: [UUID: BellRecord]

    nonisolated init() {
        bellRecords = []
        bells = []
        recordsByID = [:]
    }

    /// Maps bell records without media bytes. Book-only entities are ignored in the Bells app.
    nonisolated init(
        coverPhotoIDByItemID: [UUID: UUID],
        itemEntities: [NSManagedObject],
        collectionEntities: [NSManagedObject],
        publisherEntities: [NSManagedObject],
        personEntities: [NSManagedObject]
    ) {
        bellRecords = itemEntities.compactMap { itemEntity in
            guard let bellEntity = itemEntity.value(forKey: "bell") as? NSManagedObject else { return nil }
            return CoreDataDomainMapper.bellRecord(from: bellEntity, includesMediaData: false)
        }
        bells = bellRecords.map { Self.bellCatalogItem(from: $0, coverPhotoID: coverPhotoIDByItemID[$0.id]) }
        recordsByID = Dictionary(uniqueKeysWithValues: bellRecords.map { ($0.id, $0) })
    }

    nonisolated private static func bellCatalogItem(from record: BellRecord, coverPhotoID: UUID?) -> BellCatalogItem {
        BellCatalogItem(
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
            coverPhotoID: coverPhotoID,
            hasOrigin: record.originPlace != nil,
            hasStorage: record.item.locationID != nil
        )
    }
}

extension CatalogSnapshot {
    var bellRecords: [BellRecord] { records.bellRecords }
    var bells: [BellCatalogItem] { records.bells }
    var recordsByID: [UUID: BellRecord] { records.recordsByID }
}
