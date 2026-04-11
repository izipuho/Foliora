import SwiftUI

@main
struct CatalogApp: App {
    private let container = AppContainer.preview

    var body: some Scene {
        WindowGroup {
            HomeView(repository: container.repository)
        }
    }
}
