import Foundation

/// Defines the supported collection delete resolution values.
enum CollectionDeleteResolution {
    case deletePrivateCollection
    case deleteSharedCollectionAsOwner
    case leaveSharedCollectionAsParticipant
}

/// Defines the interface for catalog repository implementations.
@MainActor
protocol CatalogRepository {
    func saveHome(_ home: Home)
    func saveLocations(_ locations: [Location], in homeID: UUID)
    func deleteHome(homeID: UUID)
    func saveCollection(_ collection: Collection)
    func deleteResolution(for collectionID: UUID) -> CollectionDeleteResolution
    func deleteCollection(collectionID: UUID)
    func saveUserSortOrder(itemIDs: [UUID], scope: String)
    func saveItemRecord(_ item: ItemRecord)
    func saveItemRecords(_ items: [ItemRecord])
}

extension CatalogRepository {
    func saveItemRecords(_ items: [ItemRecord]) {
        items.forEach(saveItemRecord)
    }
}
