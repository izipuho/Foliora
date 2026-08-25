import CoreData
import Foundation

@MainActor
struct BellCatalogTransferAdapter: CatalogDomainTransferAdapter {
    func exportPayloads(
        from context: NSManagedObjectContext,
        itemIDs: Set<UUID>
    ) throws -> [CatalogDomainPayload] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BellEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "item.createdAt", ascending: false)]

        let items = try context.fetch(request).compactMap { bell -> BellCatalogTransferItem? in
            guard let item = bell.value(forKey: "item") as? NSManagedObject,
                  let itemID = item.value(forKey: "id") as? UUID,
                  itemIDs.contains(itemID)
            else {
                return nil
            }

            return BellCatalogTransferItem(
                itemID: itemID,
                material: bell.value(forKey: "material") as? String ?? "unknown",
                customMaterialName: bell.value(forKey: "customMaterialName") as? String
            )
        }

        guard !items.isEmpty else { return [] }
        let payload = BellCatalogTransferPayload(items: items)
        return [
            CatalogDomainPayload(
                domain: BellCatalogTransferPayload.domain,
                version: BellCatalogTransferPayload.version,
                data: try JSONEncoder().encode(payload)
            )
        ]
    }

    func filteredPayloads(
        _ payloads: [CatalogDomainPayload],
        itemIDs: Set<UUID>
    ) -> [CatalogDomainPayload] {
        payloads.compactMap { payload in
            guard payload.domain == BellCatalogTransferPayload.domain else {
                return payload
            }
            guard var bellPayload = try? JSONDecoder().decode(BellCatalogTransferPayload.self, from: payload.data) else {
                return nil
            }
            bellPayload.items = bellPayload.items.filter { itemIDs.contains($0.itemID) }
            guard !bellPayload.items.isEmpty,
                  let data = try? JSONEncoder().encode(bellPayload)
            else {
                return nil
            }
            return CatalogDomainPayload(domain: payload.domain, version: payload.version, data: data)
        }
    }

    func applyPayloads(
        _ payloads: [CatalogDomainPayload],
        itemEntitiesByID: [UUID: NSManagedObject],
        in context: NSManagedObjectContext
    ) {
        for payload in payloads where payload.domain == BellCatalogTransferPayload.domain {
            guard let bellPayload = try? JSONDecoder().decode(BellCatalogTransferPayload.self, from: payload.data) else {
                continue
            }

            for bell in bellPayload.items {
                guard let itemEntity = itemEntitiesByID[bell.itemID] else { continue }
                itemEntity.setValue(CollectionKind.bells.rawValue, forKey: "kind")

                let bellEntity = (itemEntity.value(forKey: "bell") as? NSManagedObject)
                    ?? fetchBellEntity(for: itemEntity, in: context)
                    ?? NSEntityDescription.insertNewObject(forEntityName: "BellEntity", into: context)

                bellEntity.setValue(bell.material, forKey: "material")
                bellEntity.setValue(bell.customMaterialName, forKey: "customMaterialName")
                bellEntity.setValue(itemEntity, forKey: "item")
                itemEntity.setValue(bellEntity, forKey: "bell")
            }
        }
    }

    func deleteDomainEntities(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BellEntity")
        try context.fetch(request).forEach(context.delete)
    }

    private func fetchBellEntity(
        for item: NSManagedObject,
        in context: NSManagedObjectContext
    ) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BellEntity")
        request.predicate = NSPredicate(format: "item == %@", item)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}

@MainActor
enum CatalogDomainTransferAdapterFactory {
    static func make() -> any CatalogDomainTransferAdapter {
        BellCatalogTransferAdapter()
    }
}
