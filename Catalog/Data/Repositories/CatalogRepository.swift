import Foundation

protocol CatalogRepository {
    func fetchCollections() -> [CollectionSummary]
    func fetchBellItems(for collectionID: UUID) -> [BellItem]
    func fetchCollaborators(for collectionID: UUID) -> [Collaborator]
}
