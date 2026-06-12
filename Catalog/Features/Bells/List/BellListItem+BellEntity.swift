import Foundation
import SwiftData

extension BellListItem {
    init(bell: BellEntity) {
        let coverPhoto = bell.coverPhotoAsset
        self.init(
            id: bell.id,
            title: bell.title,
            notes: bell.notes,
            acquiredYear: bell.acquiredYear,
            createdAt: bell.createdAt,
            collectionID: bell.collection?.id,
            locationID: bell.location?.id,
            placeDisplayName: bell.placeDisplayName,
            countryCode: bell.originPlace?.countryCode ?? "",
            countryName: bell.countryName,
            regionName: bell.originPlace?.regionName ?? "",
            cityName: bell.cityName,
            condition: bell.condition,
            acquisitionMethod: bell.acquisitionMethod,
            material: bell.material,
            materialDisplayName: bell.materialDisplayName,
            tagValues: bell.tagValues,
            storageFloor: bell.location?.storagePath.floor ?? "",
            storageRoom: bell.location?.storagePath.room ?? "",
            storageCabinet: bell.location?.storagePath.cabinet ?? "",
            storageShelf: bell.location?.storagePath.shelf ?? "",
            coverPhotoIdentifier: coverPhoto?.localIdentifier,
            coverPhotoThumbnailData: coverPhoto?.thumbnailData,
            coverPhotoOriginalData: coverPhoto?.originalData,
            hasOrigin: bell.originPlace != nil,
            hasStorage: bell.location != nil
        )
    }
}
