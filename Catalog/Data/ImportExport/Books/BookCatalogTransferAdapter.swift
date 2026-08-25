import CoreData
import Foundation

@MainActor
struct BookCatalogTransferAdapter: CatalogDomainTransferAdapter {
    func exportPayloads(
        from context: NSManagedObjectContext,
        itemIDs: Set<UUID>
    ) throws -> [CatalogDomainPayload] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "item.createdAt", ascending: false)]

        let items = try context.fetch(request).compactMap { entity -> BookCatalogTransferItem? in
            guard let item = entity.value(forKey: "item") as? NSManagedObject,
                  let itemID = item.value(forKey: "id") as? UUID,
                  itemIDs.contains(itemID)
            else {
                return nil
            }

            let record = CoreDataDomainMapper.bookRecord(from: entity)
            return BookCatalogTransferItem(itemID: itemID, details: record.details)
        }

        guard !items.isEmpty else { return [] }
        let payload = BookCatalogTransferPayload(items: items)
        return [
            CatalogDomainPayload(
                domain: BookCatalogTransferPayload.domain,
                version: BookCatalogTransferPayload.version,
                data: try JSONEncoder().encode(payload)
            )
        ]
    }

    func filteredPayloads(
        _ payloads: [CatalogDomainPayload],
        itemIDs: Set<UUID>
    ) -> [CatalogDomainPayload] {
        payloads.compactMap { payload in
            guard payload.domain == BookCatalogTransferPayload.domain else {
                return payload
            }
            guard var bookPayload = try? JSONDecoder().decode(BookCatalogTransferPayload.self, from: payload.data) else {
                return nil
            }
            bookPayload.items = bookPayload.items.filter { itemIDs.contains($0.itemID) }
            guard !bookPayload.items.isEmpty,
                  let data = try? JSONEncoder().encode(bookPayload)
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
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )

        for payload in payloads where payload.domain == BookCatalogTransferPayload.domain {
            guard let bookPayload = try? JSONDecoder().decode(BookCatalogTransferPayload.self, from: payload.data) else {
                continue
            }

            for transferredBook in bookPayload.items {
                guard let itemEntity = itemEntitiesByID[transferredBook.itemID] else { continue }
                itemEntity.setValue(CollectionKind.books.rawValue, forKey: "kind")

                let item = CoreDataDomainMapper.itemRecord(from: itemEntity)
                let sourceDetails = transferredBook.details
                let details = BookDetails(
                    itemID: item.id,
                    languageCode: sourceDetails.languageCode,
                    pageCount: sourceDetails.pageCount,
                    publicationPlaceName: sourceDetails.publicationPlaceName,
                    publicationYear: sourceDetails.publicationYear,
                    volumeNumber: sourceDetails.volumeNumber,
                    publicationPlace: sourceDetails.publicationPlace,
                    contributors: sourceDetails.contributors
                )
                repository.saveBookRecord(BookRecord(item: item, details: details))
            }
        }
    }

    func deleteDomainEntities(in context: NSManagedObjectContext) throws {
        for entityName in ["BookContributorEntity", "BookEntity", "PersonEntity"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            try context.fetch(request).forEach(context.delete)
        }
    }
}

@MainActor
enum CatalogDomainTransferAdapterFactory {
    static func make() -> any CatalogDomainTransferAdapter {
        BookCatalogTransferAdapter()
    }
}
