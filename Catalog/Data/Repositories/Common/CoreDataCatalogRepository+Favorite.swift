import CoreData
import Foundation

extension CoreDataCatalogRepository {
    func setFavorite(_ isFavorite: Bool, for itemID: UUID) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
        request.predicate = NSPredicate(format: "id == %@", itemID as NSUUID)
        request.fetchLimit = 1

        guard let item = try? context.fetch(request).first else { return }

        item.setValue(isFavorite, forKey: "isFavorite")
        saveContext()

        let collectionID = (item.value(forKey: "collection") as? NSManagedObject)?
            .value(forKey: "id") as? UUID

        NotificationCenter.default.post(
            name: .catalogItemFavoriteDidChange,
            object: CatalogItemFavoriteChange(
                itemID: itemID,
                collectionID: collectionID,
                isFavorite: isFavorite
            )
        )
    }
}
