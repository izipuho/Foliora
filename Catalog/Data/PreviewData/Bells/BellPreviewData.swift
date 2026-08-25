import CoreData
import Foundation

@MainActor
extension PreviewData {
    static func populateMinimalBells(context: NSManagedObjectContext) {
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let core = makeCoreMinimal(collectionKind: .bells)
        let items = makeMinimalBellItems(from: core)

        saveCore(core, using: repository)
        repository.saveItemRecords(items.map(\.item))
        saveBellDetails(items, in: context)
    }

    private static func makeMinimalBellItems(
        from core: CoreMinimal
    ) -> [(item: ItemRecord, material: String)] {
        let materials = ["unknown", "brass", "ceramic"]

        return zip(core.items, materials).enumerated().map { index, pair in
            var item = pair.0
            let material = pair.1

            switch index {
            case 0:
                item.isFavorite = true
                item.mediaAssets = [
                    makePreviewPhoto(itemID: item.id, resourcePath: "Media/IMG_8938.HEIC", sortOrder: 0)
                ]
            case 2:
                item.isFavorite = true
                item.mediaAssets = [
                    makePreviewPhoto(itemID: item.id, resourcePath: "Media/IMG_8934.HEIC", sortOrder: 0),
                    makePreviewPhoto(itemID: item.id, resourcePath: "Media/IMG_8937.HEIC", sortOrder: 1)
                ]
            default:
                item.mediaAssets = []
            }

            return (item, material)
        }
    }

    private static func saveBellDetails(
        _ items: [(item: ItemRecord, material: String)],
        in context: NSManagedObjectContext
    ) {
        for previewItem in items {
            guard let item = fetchEntity(named: "ItemEntity", by: previewItem.item.id, in: context) else {
                continue
            }

            let bell = NSEntityDescription.insertNewObject(forEntityName: "BellEntity", into: context)
            bell.setValue(previewItem.material, forKey: "material")
            bell.setValue(nil, forKey: "customMaterialName")
            bell.setValue(item, forKey: "item")
            item.setValue(bell, forKey: "bell")
        }

        try? context.save()
    }

    private static func fetchEntity(
        named entityName: String,
        by id: UUID,
        in context: NSManagedObjectContext
    ) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

@MainActor
extension PreviewContainer {
    static func makeBellsMinimal() -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeInMemoryContainer()
            PreviewData.populateMinimalBells(context: container.viewContext)
            return container
        } catch {
            fatalError("Failed to create bells preview container: \(error)")
        }
    }
}
