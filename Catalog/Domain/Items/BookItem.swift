import Foundation

/// Defines a person's contribution to a book.
struct BookContributor: Hashable, Codable {
    var role: BookContributorRole
    var order: Int
    var person: Person
}

/// Defines the supported book contributor roles.
enum BookContributorRole: String, CaseIterable, Hashable, Identifiable, Codable {
    case author
    case translator
    case editor
    case illustrator

    var id: String { rawValue }
}

/// Represents book-specific details attached to a catalog item.
struct BookDetails: Identifiable, Hashable, Codable {
    let itemID: UUID
    var languageCode: String?
    var pageCount: Int?
    var publicationYear: Int?
    var volumeNumber: Int?
    var publisher: Publisher? = nil
    var contributors: [BookContributor]
    var series: BookSeries? = nil

    var id: UUID { itemID }
}

/// Represents a complete book catalog record.
struct BookRecord: Identifiable, Hashable {
    let item: ItemRecord
    let details: BookDetails

    var id: UUID { item.id }
    var title: String { item.title }
    var collectionID: UUID { item.collectionID }
    var locationID: UUID? { item.locationID }
    var originPlaceID: UUID? { item.originPlaceID }
    var createdAt: Date { item.createdAt }
    var createdBy: String { item.createdBy }
    var notes: String { item.notes }
    var acquiredYear: Int? { item.acquiredYear }
    var condition: ItemCondition { item.condition }
    var acquisitionMethod: AcquisitionMethod { item.acquisitionMethod }
    var isFavorite: Bool { item.isFavorite }
    var tags: [String] { item.tags }
    var originPlace: Place? { item.originPlace }
    var storageLocation: Location? { item.storageLocation }
    var storagePath: StoragePath? { item.storagePath }
    var mediaAssets: [MediaAsset] { item.mediaAssets }

    var photoCount: Int { mediaAssets.filter { $0.kind == .photo }.count }
    var documentCount: Int { mediaAssets.filter { $0.kind == .document }.count }
}

extension BookRecord {
    func moving(
        to location: Location?,
        storagePath: StoragePath?
    ) -> BookRecord {
        var updatedItem = item
        updatedItem.setStorageLocation(location, path: storagePath)
        return BookRecord(item: updatedItem, details: details)
    }
}
