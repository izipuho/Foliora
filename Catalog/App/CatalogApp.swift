import SwiftUI
import SwiftData

@main
struct CatalogApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppShellView(repository: container.repository)
                .modelContainer(container.swiftDataContainer)
        }
    }
}
