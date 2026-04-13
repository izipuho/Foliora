import Foundation

struct AppContainer {
    let repository: any CatalogRepository

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    init(cloudKitConfiguration: CloudKitConfiguration = .default) {
        self.repository = CloudKitCatalogRepository(configuration: cloudKitConfiguration)
    }
}
 
