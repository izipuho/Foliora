import SwiftUI

@main
struct CatalogApp: App {
    private let container = AppContainer(repository: InMemoryCatalogRepository())

    var body: some Scene {
        WindowGroup {
            AppShellView(repository: container.repository)
        }
    }
}
