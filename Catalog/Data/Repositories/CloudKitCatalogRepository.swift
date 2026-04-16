import CloudKit
import Foundation

@MainActor
final class CloudKitCatalogRepository: CatalogRepository {
    private let configuration: CloudKitConfiguration
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let fallbackRepository: any CatalogRepository

    init(
        configuration: CloudKitConfiguration = .default,
        fallbackRepository: any CatalogRepository = InMemoryCatalogRepository()
    ) {
        self.configuration = configuration
        self.container = CKContainer(identifier: configuration.containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
        self.sharedDatabase = container.sharedCloudDatabase
        self.fallbackRepository = fallbackRepository
    }

    var containerIdentifier: String {
        configuration.containerIdentifier
    }

    var databaseScopeSummary: String {
        "Shared-first CloudKit model with owner-managed reference data."
    }

    func fetchHomes() -> [Home] {
        fallbackRepository.fetchHomes()
    }

    func fetchLocations(in homeID: UUID) -> [Location] {
        fallbackRepository.fetchLocations(in: homeID)
    }

    func fetchDomainCollections(in homeID: UUID) -> [Collection] {
        fallbackRepository.fetchDomainCollections(in: homeID)
    }

    func fetchMemberships(for collectionID: UUID) -> [Membership] {
        fallbackRepository.fetchMemberships(for: collectionID)
    }

    func fetchCollections() -> [CollectionSummary] {
        fallbackRepository.fetchCollections()
    }

    func fetchBellRecords(for collectionID: UUID) -> [BellRecord] {
        fallbackRepository.fetchBellRecords(for: collectionID)
    }

    func fetchCollaborators(for collectionID: UUID) -> [Collaborator] {
        fallbackRepository.fetchCollaborators(for: collectionID)
    }

    func saveHome(_ home: Home) {
        fallbackRepository.saveHome(home)
    }

    func saveLocations(_ locations: [Location], in homeID: UUID) {
        fallbackRepository.saveLocations(locations, in: homeID)
    }

    func deleteHome(homeID: UUID) {
        fallbackRepository.deleteHome(homeID: homeID)
    }

    func saveCollection(_ collection: Collection) {
        fallbackRepository.saveCollection(collection)
    }

    func deleteCollection(collectionID: UUID) {
        fallbackRepository.deleteCollection(collectionID: collectionID)
    }

    func saveBellRecord(_ bell: BellRecord) {
        fallbackRepository.saveBellRecord(bell)
    }

    func deleteBellRecord(bellID: UUID) {
        fallbackRepository.deleteBellRecord(bellID: bellID)
    }
}

enum CloudKitSchema {
    static let homeRecordType = "Home"
    static let locationRecordType = "Location"
    static let collectionRecordType = "Collection"
    static let itemRecordType = "Item"
    static let bellDetailsRecordType = "BellDetails"
    static let placeRecordType = "Place"
    static let mediaAssetRecordType = "MediaAsset"
}
