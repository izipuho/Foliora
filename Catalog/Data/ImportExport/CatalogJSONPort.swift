import Foundation
import SwiftData

@MainActor
enum CatalogJSONPort {
    static func exportBundle(from repository: any CatalogRepository) -> CatalogTransferBundle {
        let homes = repository.fetchHomes()
        let locations = homes.flatMap { repository.fetchLocations(in: $0.id) }
        let collections = homes.flatMap { repository.fetchDomainCollections(in: $0.id) }
        let memberships = collections.flatMap { repository.fetchMemberships(for: $0.id) }
        let bellRecords = collections
            .filter { $0.kind == .bells }
            .flatMap { repository.fetchBellRecords(for: $0.id) }

        let places = Array(Set(bellRecords.compactMap(\.originPlace)))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let bellItems = bellRecords.map { bell in
            BellTransferItem(
                item: bell.item,
                details: bell.details,
                mediaAssets: bell.mediaAssets,
                createdBy: bell.createdBy,
                tags: bell.tags
            )
        }

        return CatalogTransferBundle(
            homes: homes,
            locations: locations,
            collections: collections,
            memberships: memberships,
            places: places,
            bellItems: bellItems,
            userDirectory: defaultUserDirectory
        )
    }

    static func exportData(from repository: any CatalogRepository) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportBundle(from: repository))
    }

    static func `import`(data: Data, into repository: SwiftDataCatalogRepository) throws {
        let decoder = JSONDecoder()
        let bundle = try decoder.decode(CatalogTransferBundle.self, from: data)
        repository.replaceAllData(with: bundle)
    }

    private static let defaultUserDirectory: [String: String] = [
        "me": "Вы",
        "marina": "Марина",
        "alexey": "Алексей",
        "nina": "Нина"
    ]
}
