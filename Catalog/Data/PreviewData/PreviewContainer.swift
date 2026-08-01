import CoreData

@MainActor
enum PreviewContainer {
    static let container: NSPersistentCloudKitContainer = {
        do {
            return try FolioraCoreDataStack.makeContainer(inMemory: true)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()

    static var context: NSManagedObjectContext {
        container.viewContext
    }
}
