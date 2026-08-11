import Foundation
import CoreData

/// Represents app container data and behavior.
@MainActor
struct AppContainer {
    let repository: any CatalogRepository

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    init(coreDataContainer: NSPersistentCloudKitContainer) {
        self.repository = CoreDataCatalogRepository(context: coreDataContainer.viewContext)
    }
}
 
