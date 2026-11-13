import CoreData
import Foundation

extension CoreDataCatalogRepository {
    func requireCollectionEntity(id: UUID) -> NSManagedObject {
        guard let collection = fetchEntity(named: "CollectionEntity", by: id) else {
            preconditionFailure("CollectionEntity does not exist: \(id)")
        }
        return collection
    }

    func collectionOwnedEntity(
        named entityName: String,
        id: UUID,
        in collection: NSManagedObject
    ) -> NSManagedObject {
        let existingEntity = fetchEntity(named: entityName, by: id)
        if let existingCollection = existingEntity?.value(forKey: "collection") as? NSManagedObject,
           existingCollection != collection {
            preconditionFailure("\(entityName) cannot be shared across collections.")
        }

        let entity = existingEntity ?? makeEntity(named: entityName)
        if existingEntity == nil,
           let store = collection.objectID.persistentStore {
            context.assign(entity, to: store)
        }

        entity.setValue(id, forKey: "id")
        entity.setValue(collection, forKey: "collection")
        return entity
    }

    func canonicalCopies(
        named entityName: String,
        canonicalID: UUID,
        excluding physicalID: UUID
    ) -> [NSManagedObject] {
        fetchEntities(
            named: entityName,
            predicate: NSPredicate(
                format: "canonicalID == %@ AND id != %@",
                canonicalID as NSUUID,
                physicalID as NSUUID
            )
        )
    }
}
