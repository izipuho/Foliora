#if DEBUG
import CoreData
import Foundation

@MainActor
extension PreviewContainer {
    /// In-memory store with the fixed UI-test books (see `PreviewData.saveUITestingCore`).
    static func makeUITesting() -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeInMemoryContainer()
            let repository = CoreDataCatalogRepository(
                context: container.viewContext,
                persistentContainer: nil
            )
            let books = PreviewData.saveUITestingCore(collectionKind: .books, using: repository)
                .map { item in
                    let record = PreviewData.makeUITestingItemRecord(item)
                    return BookRecord(
                        item: record,
                        details: BookDetails(itemID: record.id, contributors: [])
                    )
                }
            repository.saveBookRecords(books)
            return container
        } catch {
            fatalError("Failed to create UI testing container: \(error)")
        }
    }
}
#endif
