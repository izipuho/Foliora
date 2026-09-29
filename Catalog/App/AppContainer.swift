import Foundation
import CoreData

/// Represents app container data and behavior.
@MainActor
struct AppContainer {
    let repository: any AppRepository
    let mediaDataLoader: MediaDataLoader?

    init(repository: any AppRepository, mediaDataLoader: MediaDataLoader? = nil) {
        self.repository = repository
        self.mediaDataLoader = mediaDataLoader
    }

    init(coreDataContainer: NSPersistentCloudKitContainer) {
        self.repository = CoreDataCatalogRepository(context: coreDataContainer.viewContext)
        self.mediaDataLoader = MediaDataLoader(container: coreDataContainer)
    }
}
