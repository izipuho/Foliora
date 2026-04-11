import Foundation

struct AppContainer {
    let repository: any CatalogRepository

    static let preview = AppContainer(repository: InMemoryCatalogRepository())
}
