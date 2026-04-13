import Foundation

protocol CatalogRepository {
    func fetchHomes() -> [Home]
    func fetchLocations(in homeID: UUID) -> [Location]
    func fetchDomainCollections(in homeID: UUID) -> [Collection]
    func fetchMemberships(for collectionID: UUID) -> [Membership]
    func fetchCollections() -> [CollectionSummary]
    func fetchBellRecords(for collectionID: UUID) -> [BellRecord]
    func fetchCollaborators(for collectionID: UUID) -> [Collaborator]
    func saveHome(_ home: Home)
    func saveLocations(_ locations: [Location], in homeID: UUID)
    func deleteHome(homeID: UUID)
    func saveBellRecord(_ bell: BellRecord)
    func deleteBellRecord(bellID: UUID)
}
