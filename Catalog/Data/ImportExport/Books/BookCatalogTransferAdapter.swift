import CoreData
import Foundation

@MainActor
struct BookCatalogTransferAdapter: CatalogDomainTransferAdapter {
    private struct CanonicalReferenceKey: Hashable {
        let collectionID: UUID
        let canonicalID: UUID
    }

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
        let series = try context.fetch(seriesRequest).compactMap { CoreDataDomainMapper.bookSeries(from: $0) }

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
        var materializedPublishers: [CanonicalReferenceKey: Publisher] = [:]
        var materializedPeople: [CanonicalReferenceKey: Person] = [:]

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
                        publisher: materializedPublisher(
                            sourceSeries.publisher,
                            collectionID: localCollectionID,
                            in: context,
                            cache: &materializedPublishers
                        )
                    )
                )
            }

            for transferredBook in bookPayload.items {
                guard let itemEntity = itemEntitiesByID[transferredBook.itemID] else { continue }
                itemEntity.setValue(CollectionKind.books.rawValue, forKey: "kind")

                let item = CoreDataDomainMapper.itemRecord(from: itemEntity)
                let sourceDetails = transferredBook.details
                let publisher = materializedPublisher(
                    sourceDetails.publisher,
                    collectionID: item.collectionID,
                    in: context,
                    cache: &materializedPublishers
                )
                let contributors = sourceDetails.contributors.map { contributor in
                    BookContributor(
                        role: contributor.role,
                        order: contributor.order,
                        person: materializedPerson(
                            contributor.person,
                            collectionID: item.collectionID,
                            in: context,
                            cache: &materializedPeople
                        )
                    )
                }
                let series = sourceDetails.series.map { sourceSeries in
                    BookSeries(
                        id: sourceSeries.id,
                        collectionID: item.collectionID,
                        name: sourceSeries.name,
                        totalBookCount: sourceSeries.totalBookCount,
                        publisher: materializedPublisher(
                            sourceSeries.publisher,
                            collectionID: item.collectionID,
                            in: context,
                            cache: &materializedPublishers
                        )
                    )
                }
                let coverImage = sourceDetails.coverImage?.with(
                    itemID: item.id,
                    sortOrder: 0
                )
                let details = BookDetails(
                    itemID: item.id,
                    subtitle: sourceDetails.subtitle,
                    languageCode: sourceDetails.languageCode,
                    genre: sourceDetails.genre,
                    pageCount: sourceDetails.pageCount,
                    publicationYear: sourceDetails.publicationYear,
                    volumeNumber: sourceDetails.volumeNumber,
                    coverImage: coverImage,
                    publisher: publisher,
                    contributors: contributors,
                    series: series,
                    identifiers: sourceDetails.identifiers
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

    private func materializedPublisher(
        _ source: Publisher?,
        collectionID: UUID,
        in context: NSManagedObjectContext,
        cache: inout [CanonicalReferenceKey: Publisher]
    ) -> Publisher? {
        guard let source else { return nil }
        let key = CanonicalReferenceKey(
            collectionID: collectionID,
            canonicalID: source.canonicalID
        )

        if let cached = cache[key] {
            return cached
        }

        let existing = existingPublisher(
            canonicalID: source.canonicalID,
            collectionID: collectionID,
            in: context
        )
        let preserveSourcePhysicalIdentity = existing == nil && source.collectionID == collectionID
        let publisher = Publisher(
            id: existing?.id ?? (preserveSourcePhysicalIdentity ? source.id : UUID()),
            canonicalID: source.canonicalID,
            collectionID: collectionID,
            name: source.name,
            logo: source.logo.map { logo in
                materializedMediaAsset(
                    logo,
                    existing: existing?.logo,
                    preserveSourcePhysicalIdentity: preserveSourcePhysicalIdentity
                )
            }
        )
        cache[key] = publisher
        return publisher
    }

    private func materializedPerson(
        _ source: Person,
        collectionID: UUID,
        in context: NSManagedObjectContext,
        cache: inout [CanonicalReferenceKey: Person]
    ) -> Person {
        let key = CanonicalReferenceKey(
            collectionID: collectionID,
            canonicalID: source.canonicalID
        )

        if let cached = cache[key] {
            return cached
        }

        let existing = existingPerson(
            canonicalID: source.canonicalID,
            collectionID: collectionID,
            in: context
        )
        let preserveSourcePhysicalIdentity = existing == nil && source.collectionID == collectionID
        let existingPhotos = existing?.photos.sorted { $0.sortOrder < $1.sortOrder } ?? []
        let photos = source.photos.enumerated().map { index, photo in
            materializedMediaAsset(
                photo,
                existing: existingPhotos.indices.contains(index) ? existingPhotos[index] : nil,
                preserveSourcePhysicalIdentity: preserveSourcePhysicalIdentity
            ).with(sortOrder: index)
        }
        let person = Person(
            id: existing?.id ?? (preserveSourcePhysicalIdentity ? source.id : UUID()),
            canonicalID: source.canonicalID,
            collectionID: collectionID,
            givenName: source.givenName,
            familyName: source.familyName,
            middleName: source.middleName,
            birthYear: source.birthYear,
            deathYear: source.deathYear,
            biography: source.biography,
            birthPlace: source.birthPlace,
            deathPlace: source.deathPlace,
            photos: photos
        )
        cache[key] = person
        return person
    }

    private func existingPublisher(
        canonicalID: UUID,
        collectionID: UUID,
        in context: NSManagedObjectContext
    ) -> Publisher? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PublisherEntity")
        request.predicate = NSPredicate(
            format: "canonicalID == %@ AND collection.id == %@",
            canonicalID as NSUUID,
            collectionID as NSUUID
        )
        request.fetchLimit = 1

        guard let entity = (try? context.fetch(request))?.first else { return nil }
        return CoreDataDomainMapper.publisher(from: entity)
    }

    private func existingPerson(
        canonicalID: UUID,
        collectionID: UUID,
        in context: NSManagedObjectContext
    ) -> Person? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PersonEntity")
        request.predicate = NSPredicate(
            format: "canonicalID == %@ AND collection.id == %@",
            canonicalID as NSUUID,
            collectionID as NSUUID
        )
        request.fetchLimit = 1

        guard let entity = (try? context.fetch(request))?.first else { return nil }
        return CoreDataDomainMapper.person(from: entity)
    }

    private func materializedMediaAsset(
        _ source: MediaAsset,
        existing: MediaAsset?,
        preserveSourcePhysicalIdentity: Bool
    ) -> MediaAsset {
        MediaAsset(
            id: existing?.id ?? (preserveSourcePhysicalIdentity ? source.id : UUID()),
            itemID: nil,
            kind: source.kind,
            displayName: source.displayName,
            sortOrder: source.sortOrder,
            fileName: source.fileName,
            mimeType: source.mimeType,
            byteSize: source.byteSize,
            checksum: source.checksum,
            width: source.width,
            height: source.height,
            duration: source.duration,
            metadataJSON: source.metadataJSON,
            originalData: source.originalData
        )
    }
}

@MainActor
enum CatalogDomainTransferAdapterFactory {
    static func make() -> any CatalogDomainTransferAdapter {
        BookCatalogTransferAdapter()
    }
}
