import CoreData
import Foundation

@MainActor
struct BookCatalogTransferAdapter: CatalogDomainTransferAdapter {
    func exportPayloads(
        from context: NSManagedObjectContext,
        collectionIDs: Set<UUID>,
        itemIDs: Set<UUID>
    ) throws -> [CatalogDomainPayload] {
        let bookRequest = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
        bookRequest.sortDescriptors = [NSSortDescriptor(key: "item.createdAt", ascending: false)]

        let items = try context.fetch(bookRequest).compactMap { entity -> BookCatalogTransferItem? in
            guard let item = entity.value(forKey: "item") as? NSManagedObject,
                  let itemID = item.value(forKey: "id") as? UUID,
                  itemIDs.contains(itemID)
            else {
                return nil
            }

            let record = CoreDataDomainMapper.bookRecord(from: entity)
            return BookCatalogTransferItem(itemID: itemID, details: record.details)
        }

        let seriesRequest = NSFetchRequest<NSManagedObject>(entityName: "BookSeriesEntity")
        seriesRequest.predicate = NSPredicate(
            format: "collection.id IN %@",
            collectionIDs.map { $0 as NSUUID }
        )
        seriesRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let series = try context.fetch(seriesRequest).map(CoreDataDomainMapper.bookSeries)

        guard !items.isEmpty || !series.isEmpty else { return [] }
        let payload = BookCatalogTransferPayload(items: items, series: series)
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
        collectionIDs: Set<UUID>,
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
            bookPayload.series = bookPayload.series.filter { collectionIDs.contains($0.collectionID) }
            guard (!bookPayload.items.isEmpty || !bookPayload.series.isEmpty),
                  let data = try? JSONEncoder().encode(bookPayload)
            else {
                return nil
            }
            return CatalogDomainPayload(domain: payload.domain, version: payload.version, data: data)
        }
    }

    func applyPayloads(
        _ payloads: [CatalogDomainPayload],
        collectionEntitiesByID: [UUID: NSManagedObject],
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

            for sourceSeries in bookPayload.series {
                guard let collectionEntity = collectionEntitiesByID[sourceSeries.collectionID],
                      let localCollectionID = collectionEntity.value(forKey: "id") as? UUID
                else {
                    continue
                }

                repository.saveBookSeries(
                    BookSeries(
                        id: sourceSeries.id,
                        collectionID: localCollectionID,
                        name: sourceSeries.name,
                        totalBookCount: sourceSeries.totalBookCount,
                        publisher: sourceSeries.publisher
                    )
                )
            }

            for transferredBook in bookPayload.items {
                guard let itemEntity = itemEntitiesByID[transferredBook.itemID] else { continue }
                itemEntity.setValue(CollectionKind.books.rawValue, forKey: "kind")

                let item = CoreDataDomainMapper.itemRecord(from: itemEntity)
                let sourceDetails = transferredBook.details
                let series = sourceDetails.series.map {
                    BookSeries(
                        id: $0.id,
                        collectionID: item.collectionID,
                        name: $0.name,
                        totalBookCount: $0.totalBookCount,
                        publisher: $0.publisher
                    )
                }
                let details = BookDetails(
                    itemID: item.id,
                    languageCode: sourceDetails.languageCode,
                    pageCount: sourceDetails.pageCount,
                    publicationYear: sourceDetails.publicationYear,
                    volumeNumber: sourceDetails.volumeNumber,
                    publisher: sourceDetails.publisher,
                    contributors: sourceDetails.contributors,
                    series: series
                )
                repository.saveBookRecord(BookRecord(item: item, details: details))
            }
        }
    }

    func deleteDomainEntities(in context: NSManagedObjectContext) throws {
        for entityName in ["BookContributorEntity", "BookEntity", "BookSeriesEntity", "PublisherEntity", "PersonEntity"] {
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
