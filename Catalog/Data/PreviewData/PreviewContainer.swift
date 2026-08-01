import CoreData

enum PreviewScenario {
    case empty
    case minimal
}

@MainActor
enum PreviewContainer {
    static func make(_ scenario: PreviewScenario) -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeContainer(inMemory: true)

            switch scenario {
            case .empty:
                return container
            case .minimal:
                return container
            }
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}
