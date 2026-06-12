import Foundation
import CoreData
import SwiftData

@MainActor
struct AppContainer {
    let swiftDataContainer: ModelContainer
    let repository: any CatalogRepository

    init(swiftDataContainer: ModelContainer, repository: any CatalogRepository) {
        self.swiftDataContainer = swiftDataContainer
        self.repository = repository
    }

    init(coreDataContainer: NSPersistentCloudKitContainer) {
        do {
            let container = try CatalogSwiftDataStack.makeContainer()
            self.swiftDataContainer = container
            self.repository = CoreDataCatalogRepository(context: coreDataContainer.viewContext)
            print("Catalog repository backend: Core Data")
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }
}
 
