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
        // Passed explicitly: the app delegate learns about the container only after this initializer.
        self.repository = CoreDataCatalogRepository(
            context: coreDataContainer.viewContext,
            persistentContainer: coreDataContainer
        )
        self.mediaDataLoader = MediaDataLoader(container: coreDataContainer)
    }
}
