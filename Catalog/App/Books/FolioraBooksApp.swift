import CoreData
import SwiftUI

/// Provides the Foliora Books application entry point.
@main
struct FolioraBooksApp: App {
    @State private var coreDataContainer: NSPersistentCloudKitContainer?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            content
                .task {
                    await prepareApplicationIfNeeded()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let coreDataContainer {
            BookLibraryView()
                .environment(\.managedObjectContext, coreDataContainer.viewContext)
        } else if let startupError {
            ContentUnavailableView(
                "Unable to Open Library",
                systemImage: "books.vertical",
                description: Text(startupError)
            )
        } else {
            ProgressView("Preparing library")
        }
    }

    @MainActor
    private func prepareApplicationIfNeeded() async {
        guard coreDataContainer == nil, startupError == nil else { return }

        do {
            coreDataContainer = try await FolioraCoreDataStack.makeContainer()
        } catch {
            startupError = error.localizedDescription
        }
    }
}
