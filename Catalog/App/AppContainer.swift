import Foundation
import CoreData

@MainActor
struct AppContainer {
    let repository: any CatalogRepository

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    init(coreDataContainer: NSPersistentCloudKitContainer) {
        self.repository = CoreDataCatalogRepository(context: coreDataContainer.viewContext)
        print("Catalog repository backend: Core Data")
    }
}
 
