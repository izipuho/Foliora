import CoreData

enum PreviewScenario {
    case empty
    case minimal
}

@MainActor
enum PreviewContainer {
    static func make(_ scenario: PreviewScenario) -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeInMemoryContainer()

            switch scenario {
            case .empty:
                return container
            case .minimal:
                PreviewData.populateMinimal(context: container.viewContext)
                return container
            }
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}
