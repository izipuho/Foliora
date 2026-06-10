import Foundation
import SwiftData

enum CatalogSwiftDataStack {
    static let schema = Schema([
        HomeEntity.self,
        LocationEntity.self,
        CollectionEntity.self,
        PlaceEntity.self,
        BellEntity.self,
        BellTagEntity.self,
        MediaAssetEntity.self
    ])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let storeURL = try persistentStoreURL()
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .private(CloudKitConfiguration.containerIdentifier))
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func persistentStoreURL() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("catalog.store")
    }
}
