import Foundation

/// Represents bell list item data and behavior.
struct BellListItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let notes: String
    let isFavorite: Bool
    let acquiredYear: Int?
    let createdAt: Date
    let collectionID: UUID?
    let locationID: UUID?
    let placeDisplayName: String
    let originLatitude: Double?
    let originLongitude: Double?
    let countryCode: String
    let countryName: String
    let regionName: String
    let cityName: String
    let condition: ItemCondition
    let acquisitionMethod: AcquisitionMethod
    let material: BellMaterial
    let materialDisplayName: String
    let tagValues: [String]
    let storagePath: StoragePath?
    let storageFloor: String
    let storageRoom: String
    let storageCabinet: String
    let storageShelf: String
    let storageDisplayPath: String
    let storageLocationName: String
    let coverPhotoIdentifier: String?
    let coverPhotoThumbnailData: Data?
    let coverPhotoOriginalData: Data?
    let hasOrigin: Bool
    let hasStorage: Bool

    init(
        id: UUID,
        title: String,
        notes: String,
        isFavorite: Bool,
        acquiredYear: Int?,
        createdAt: Date,
        collectionID: UUID?,
        locationID: UUID?,
        placeDisplayName: String,
        originLatitude: Double?,
        originLongitude: Double?,
        countryCode: String,
        countryName: String,
        regionName: String,
        cityName: String,
        condition: ItemCondition,
        acquisitionMethod: AcquisitionMethod,
        material: BellMaterial,
        materialDisplayName: String,
        tagValues: [String],
        storagePath: StoragePath? = nil,
        storageFloor: String,
        storageRoom: String,
        storageCabinet: String,
        storageShelf: String,
        storageDisplayPath: String,
        storageLocationName: String,
        coverPhotoIdentifier: String?,
        coverPhotoThumbnailData: Data?,
        coverPhotoOriginalData: Data?,
        hasOrigin: Bool,
        hasStorage: Bool
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isFavorite = isFavorite
        self.acquiredYear = acquiredYear
        self.createdAt = createdAt
        self.collectionID = collectionID
        self.locationID = locationID
        self.placeDisplayName = placeDisplayName
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.countryCode = countryCode
        self.countryName = countryName
        self.regionName = regionName
        self.cityName = cityName
        self.condition = condition
        self.acquisitionMethod = acquisitionMethod
        self.material = material
        self.materialDisplayName = materialDisplayName
        self.tagValues = tagValues
        self.storagePath = storagePath
        self.storageFloor = storageFloor
        self.storageRoom = storageRoom
        self.storageCabinet = storageCabinet
        self.storageShelf = storageShelf
        self.storageDisplayPath = storageDisplayPath
        self.storageLocationName = storageLocationName
        self.coverPhotoIdentifier = coverPhotoIdentifier
        self.coverPhotoThumbnailData = coverPhotoThumbnailData
        self.coverPhotoOriginalData = coverPhotoOriginalData
        self.hasOrigin = hasOrigin
        self.hasStorage = hasStorage
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
