import Foundation
import SwiftData

@MainActor
protocol CatalogRepository {
    var modelContainer: ModelContainer { get }
    func saveHome(_ home: Home)
    func saveLocations(_ locations: [Location], in homeID: UUID)
    func deleteHome(homeID: UUID)
    func saveCollection(_ collection: Collection)
    func deleteCollection(collectionID: UUID)
    func saveBellRecord(_ bell: BellRecord)
    func saveBellRecords(_ bells: [BellRecord])
    func deleteBellRecord(bellID: UUID)
}

extension CatalogRepository {
    func saveBellRecords(_ bells: [BellRecord]) {
        bells.forEach(saveBellRecord)
    }
}
