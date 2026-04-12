import Foundation

protocol CatalogRepository {
    func fetchCollections() -> [CollectionSummary]
    func fetchBellRecords(for collectionID: UUID) -> [BellRecord]
    func fetchCollaborators(for collectionID: UUID) -> [Collaborator]
}
