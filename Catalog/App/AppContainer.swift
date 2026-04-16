import Foundation
import SwiftData

@MainActor
struct AppContainer {
    let swiftDataContainer: ModelContainer
    let repository: any CatalogRepository

    init(swiftDataContainer: ModelContainer, repository: any CatalogRepository) {
        self.swiftDataContainer = swiftDataContainer
        self.repository = repository
    }

    init() {
        do {
            let container = try CatalogSwiftDataStack.makeContainer()
            self.swiftDataContainer = container
            self.repository = SwiftDataCatalogRepository(container: container)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }
}
 
