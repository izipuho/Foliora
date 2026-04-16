import Foundation

@MainActor
struct AppContainer {
    let repository: any CatalogRepository

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    init() {
        self.repository = LocalCatalogRepository()
    }
}
 
