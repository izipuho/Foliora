import SwiftUI

@main
struct CatalogApp: App {
    private let store = CatalogStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
