import CoreData
import Foundation

extension CatalogSnapshot {
    var recordsByID: [UUID: BellRecord] {
        bellRecordsByID
    }

    /// Maps bell records once per snapshot load. Media is mapped without `originalData`.
    nonisolated static func mapBellRecords(from itemEntities: [NSManagedObject]) -> [BellRecord] {
        itemEntities.compactMap { itemEntity in
            guard let bellEntity = itemEntity.value(forKey: "bell") as? NSManagedObject else { return nil }
            return CoreDataDomainMapper.bellRecord(from: bellEntity, includesMediaData: false)
        }
    }

    nonisolated static func bellCatalogItem(from record: BellRecord) -> BellCatalogItem {
        let coverPhoto = record.mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { $0.kind == .photo }

        return BellCatalogItem(
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
            coverPhotoID: coverPhoto?.id,
            hasOrigin: record.originPlace != nil,
            hasStorage: record.item.locationID != nil
        )
    }
}
