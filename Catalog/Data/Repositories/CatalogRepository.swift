import Foundation

enum CollectionDeleteResolution {
    case deletePrivateCollection
    case deleteSharedCollectionAsOwner
    case leaveSharedCollectionAsParticipant
}

@MainActor
protocol CatalogRepository {
    func saveHome(_ home: Home)
    func saveLocations(_ locations: [Location], in homeID: UUID)
    func deleteHome(homeID: UUID)
    func saveCollection(_ collection: Collection)
    func deleteResolution(for collectionID: UUID) -> CollectionDeleteResolution
    func deleteCollection(collectionID: UUID)
    func saveItemRecord(_ item: ItemRecord)
    func saveItemRecords(_ items: [ItemRecord])
    func saveBellRecord(_ bell: BellRecord)
    func saveBellRecords(_ bells: [BellRecord])
    func deleteBellRecord(bellID: UUID)
}

extension CatalogRepository {
    func saveItemRecords(_ items: [ItemRecord]) {
        items.forEach(saveItemRecord)
    }

    func saveBellRecords(_ bells: [BellRecord]) {
        bells.forEach(saveBellRecord)
    }
}
