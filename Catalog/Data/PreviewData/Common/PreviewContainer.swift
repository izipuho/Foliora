import CoreData
import SwiftUI

/// Defines the supported preview scenario values.
enum PreviewScenario {
    case empty
    case coreMinimal
    case collectionsMinimal
}

/// Groups preview container values and behavior.
@MainActor
enum PreviewContainer {
    static func make(_ scenario: PreviewScenario) -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeInMemoryContainer()

            switch scenario {
            case .empty:
                return container
            case .coreMinimal:
                PreviewData.populateCoreMinimal(context: container.viewContext, collectionKind: .bells)
                return container
            case .collectionsMinimal:
                PreviewData.populateCollectionsMinimal(context: container.viewContext)
                return container
            }
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}

extension View {
    /// Injects the environment the app shell provides, backed by a preview container.
    ///
    /// Snapshot records carry media without bytes, so `MediaPreviewImage` needs
    /// `mediaDataLoader` to show saved photos in the canvas.
    func previewEnvironment(_ container: NSPersistentContainer) -> some View {
        environment(\.managedObjectContext, container.viewContext)
            .environment(\.mediaDataLoader, MediaDataLoader(container: container))
    }
}
