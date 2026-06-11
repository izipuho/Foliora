import SwiftUI
import SwiftData

@main
struct FolioraApp: App {
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppShellView(repository: container.repository)
                .modelContainer(container.swiftDataContainer)
        }
    }
}
