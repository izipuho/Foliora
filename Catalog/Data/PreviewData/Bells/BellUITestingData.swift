#if DEBUG
import CoreData
import Foundation

@MainActor
extension PreviewContainer {
    /// In-memory store with the fixed UI-test bells (see `PreviewData.saveUITestingCore`).
    static func makeUITesting() -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeInMemoryContainer()
            let repository = CoreDataCatalogRepository(
                context: container.viewContext,
                persistentContainer: nil
            )
            let bells = PreviewData.saveUITestingCore(collectionKind: .bells, using: repository)
                .map { item in
                    let record = PreviewData.makeUITestingItemRecord(item)
                    return BellRecord(
                        item: record,
                        details: BellDetails(itemID: record.id, material: .brass, customMaterialName: nil)
                    )
                }
            repository.saveBellRecords(bells)
            return container
        } catch {
            fatalError("Failed to create UI testing container: \(error)")
        }
    }
}
#endif
