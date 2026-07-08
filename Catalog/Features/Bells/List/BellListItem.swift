import Foundation

struct BellListItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let notes: String
    let acquiredYear: Int?
    let createdAt: Date
    let collectionID: UUID?
    let locationID: UUID?
    let placeDisplayName: String
    let countryCode: String
    let countryName: String
    let regionName: String
    let cityName: String
    let condition: ItemCondition
    let acquisitionMethod: AcquisitionMethod
    let material: BellMaterial
    let materialDisplayName: String
    let tagValues: [String]
    let storageFloor: String
    let storageRoom: String
    let storageCabinet: String
    let storageShelf: String
    let coverPhotoIdentifier: String?
    let coverPhotoThumbnailData: Data?
    let coverPhotoOriginalData: Data?
    let hasOrigin: Bool
    let hasStorage: Bool

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
