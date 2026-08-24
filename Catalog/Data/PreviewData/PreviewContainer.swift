import CoreData

/// Defines the supported preview scenario values.
enum PreviewScenario {
    case empty
    case minimal
    case coreMinimal
    case bellsMinimal
    case booksMinimal
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
            case .minimal, .bellsMinimal:
                PreviewData.populateMinimalBells(context: container.viewContext)
                return container
            case .coreMinimal:
                PreviewData.populateCoreMinimal(context: container.viewContext, collectionKind: .bells)
                return container
            case .booksMinimal:
                PreviewData.populateCoreMinimal(context: container.viewContext, collectionKind: .books)
                return container
            }
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}
