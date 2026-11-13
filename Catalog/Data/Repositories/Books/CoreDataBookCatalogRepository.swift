import CoreData
import Foundation

extension CoreDataCatalogRepository: BookCatalogRepository {
    func saveBookRecord(_ book: BookRecord) {
        saveBookRecordWithoutSavingContext(book)
        saveContext()
    }

    func saveBookRecords(_ books: [BookRecord]) {
        books.forEach(saveBookRecordWithoutSavingContext)
        saveContext()
    }

    func saveBookSeries(_ series: BookSeries) {
        let collection = requireCollectionEntity(id: series.collectionID)
        _ = upsertBookSeries(series, forCollection: collection)
        saveContext()
    }

    func deleteBookSeries(seriesID: UUID) {
        guard let seriesEntity = fetchEntity(named: "BookSeriesEntity", by: seriesID) else { return }

        let books = fetchEntities(
            named: "BookEntity",
            predicate: NSPredicate(format: "series == %@", seriesEntity)
        )
        for book in books {
            book.setValue(nil, forKey: "series")
            book.setValue(nil, forKey: "volumeNumber")
        }

        context.delete(seriesEntity)
        saveContext()
    }

    func savePublisher(_ publisher: Publisher) {
        _ = upsertPublisher(publisher)
        propagatePublisher(publisher)
        saveContext()
    }

    func deletePublisher(publisherID: UUID) {
        let publishers = fetchEntities(
            named: "PublisherEntity",
            predicate: NSPredicate(format: "id == %@", publisherID as NSUUID)
        )
        guard !publishers.isEmpty else { return }

        for publisher in publishers {
            relatedObjects(publisher, "books").forEach {
                $0.setValue(nil, forKey: "publisher")
            }
            relatedObjects(publisher, "bookSeries").forEach {
                $0.setValue(nil, forKey: "publisher")
            }
            if let logo = publisher.value(forKey: "logo") as? NSManagedObject {
                context.delete(logo)
            }
            context.delete(publisher)
        }

        saveContext()
    }

    func deleteBookRecord(bookID: UUID) {
        guard let entity = fetchBookEntity(by: bookID) else { return }
        guard let item = entity.value(forKey: "item") as? NSManagedObject else { return }

        context.delete(item)
        deleteOrphanItemTags()
        saveContext()
    }

    private func saveBookRecordWithoutSavingContext(_ book: BookRecord) {
        guard let item = saveItemRecordWithoutSavingContext(book.item) else { return }

        let entity = fetchBookEntity(by: book.id) ?? makeEntity(named: "BookEntity", inStoreOf: item)

        apply(book, to: entity)
        entity.setValue(item, forKey: "item")
        fillInverseRelationship(from: entity, relationshipName: "item", with: item)
        replaceBookCoverImage(book.details.coverImage, for: entity)
        entity.setValue(
            book.details.publisher.map { publisher in
                precondition(
                    publisher.collectionID == book.item.collectionID,
                    "Publisher collection does not match the book collection."
                )
                return upsertPublisher(publisher)
            },
            forKey: "publisher"
        )
        entity.setValue(book.details.series.map { upsertBookSeries($0, for: item) }, forKey: "series")
        replaceContributors(book.details.contributors, for: entity)
        replaceBookIdentifiers(book.details.identifiers, for: entity)
    }

    private func apply(_ book: BookRecord, to entity: NSManagedObject) {
        entity.setValue(book.details.subtitle, forKey: "subtitle")
        entity.setValue(book.details.languageCode, forKey: "languageCode")
        entity.setValue(book.details.genre, forKey: "genre")
        entity.setValue(book.details.pageCount, forKey: "pageCount")
        entity.setValue(book.details.publicationYear, forKey: "publicationYear")
        entity.setValue(book.details.volumeNumber, forKey: "volumeNumber")
    }

    private func upsertBookSeries(_ series: BookSeries, for item: NSManagedObject) -> NSManagedObject {
        guard let collection = item.value(forKey: "collection") as? NSManagedObject else {
            preconditionFailure("ItemEntity is missing its CollectionEntity relationship while saving BookSeriesEntity.")
        }

        return upsertBookSeries(series, forCollection: collection)
    }

    private func upsertBookSeries(_ series: BookSeries, forCollection collection: NSManagedObject) -> NSManagedObject {
        let collectionID = collection.value(forKey: "id") as? UUID
        precondition(
            collectionID == series.collectionID,
            "BookSeries collection does not match the book collection."
        )

        let entity = collectionOwnedEntity(
            named: "BookSeriesEntity",
            id: series.id,
            in: collection
        )
        entity.setValue(series.name, forKey: "name")
        entity.setValue(series.totalBookCount, forKey: "totalBookCount")
        entity.setValue(
            series.publisher.map { publisher in
                precondition(
                    publisher.collectionID == series.collectionID,
                    "Publisher collection does not match the series collection."
                )
                return upsertPublisher(publisher)
            },
            forKey: "publisher"
        )
        return entity
    }

    private func upsertPublisher(_ publisher: Publisher) -> NSManagedObject {
        let collection = requireCollectionEntity(id: publisher.collectionID)
        let entity = collectionOwnedEntity(
            named: "PublisherEntity",
            id: publisher.id,
            in: collection
        )

        entity.setValue(publisher.canonicalID, forKey: "canonicalID")
        entity.setValue(publisher.name, forKey: "name")
        replacePublisherLogo(publisher.logo, for: entity)
        return entity
    }

    private func propagatePublisher(_ publisher: Publisher) {
        let copies = canonicalCopies(
            named: "PublisherEntity",
            canonicalID: publisher.canonicalID,
            excluding: publisher.id
        )

        for copy in copies {
            guard
                let id = copy.value(forKey: "id") as? UUID,
                let collection = copy.value(forKey: "collection") as? NSManagedObject,
                let collectionID = collection.value(forKey: "id") as? UUID
            else {
                continue
            }

            let synchronized = Publisher(
                id: id,
                canonicalID: publisher.canonicalID,
                collectionID: collectionID,
                name: publisher.name,
                logo: synchronizedPublisherLogo(publisher.logo, for: copy)
            )
            _ = upsertPublisher(synchronized)
        }
    }

    private func synchronizedPublisherLogo(
        _ logo: MediaAsset?,
        for publisher: NSManagedObject
    ) -> MediaAsset? {
        guard let logo else { return nil }
        let existing = publisher.value(forKey: "logo") as? NSManagedObject

        return MediaAsset(
            id: existing?.value(forKey: "id") as? UUID ?? UUID(),
            itemID: nil,
            kind: logo.kind,
            displayName: logo.displayName,
            sortOrder: 0,
            fileName: logo.fileName,
            mimeType: logo.mimeType,
            byteSize: logo.byteSize,
            checksum: logo.checksum,
            width: logo.width,
            height: logo.height,
            duration: logo.duration,
            metadataJSON: logo.metadataJSON,
            originalData: logo.originalData ?? existing?.value(forKey: "originalData") as? Data
        )
    }

    private func replacePublisherLogo(_ logo: MediaAsset?, for publisher: NSManagedObject) {
        let existingLogo = publisher.value(forKey: "logo") as? NSManagedObject

        guard let logo else {
            publisher.setValue(nil, forKey: "logo")
            if let existingLogo {
                context.delete(existingLogo)
            }
            return
        }

        let logoEntity: NSManagedObject
        if let existingLogo,
           existingLogo.value(forKey: "id") as? UUID == logo.id {
            logoEntity = existingLogo
        } else {
            if let existingLogo {
                context.delete(existingLogo)
            }
            logoEntity = makeEntity(named: "MediaAssetEntity")
            if logoEntity.objectID.persistentStore == nil,
               let store = publisher.objectID.persistentStore {
                context.assign(logoEntity, to: store)
            }
        }

        apply(logo.with(sortOrder: 0), to: logoEntity)
        logoEntity.setValue(publisher, forKey: "publisher")
        publisher.setValue(logoEntity, forKey: "logo")
    }

    private func replaceBookCoverImage(_ coverImage: MediaAsset?, for book: NSManagedObject) {
        let existingCoverImage = book.value(forKey: "coverImage") as? NSManagedObject

        guard let coverImage else {
            book.setValue(nil, forKey: "coverImage")
            if let existingCoverImage {
                context.delete(existingCoverImage)
            }
            return
        }

        let coverImageEntity: NSManagedObject
        if let existingCoverImage,
           existingCoverImage.value(forKey: "id") as? UUID == coverImage.id {
            coverImageEntity = existingCoverImage
        } else {
            if let existingCoverImage {
                context.delete(existingCoverImage)
            }
            coverImageEntity = makeEntity(named: "MediaAssetEntity")
            if coverImageEntity.objectID.persistentStore == nil,
               let item = book.value(forKey: "item") as? NSManagedObject,
               let collection = item.value(forKey: "collection") as? NSManagedObject,
               let store = book.objectID.persistentStore
                    ?? item.objectID.persistentStore
                    ?? collection.objectID.persistentStore {
                context.assign(coverImageEntity, to: store)
            }
        }

        apply(coverImage.with(sortOrder: 0), to: coverImageEntity)
        coverImageEntity.setValue(book, forKey: "book")
        book.setValue(coverImageEntity, forKey: "coverImage")
    }

    private func replaceContributors(_ contributors: [BookContributor], for book: NSManagedObject) {
        guard let item = book.value(forKey: "item") as? NSManagedObject,
              let collection = item.value(forKey: "collection") as? NSManagedObject,
              let collectionID = collection.value(forKey: "id") as? UUID else {
            preconditionFailure("BookEntity is missing its collection while saving contributors.")
        }

        relatedObjects(book, "contributors").forEach(context.delete)

        let entities = contributors.map { contributor -> NSManagedObject in
            precondition(
                contributor.person.collectionID == collectionID,
                "Person collection does not match the book collection."
            )

            let entity = makeEntity(named: "BookContributorEntity", inStoreOf: book)
            entity.setValue(contributor.role.rawValue, forKey: "role")
            entity.setValue(contributor.order, forKey: "order")
            entity.setValue(book, forKey: "book")
            entity.setValue(upsertCatalogPerson(contributor.person), forKey: "person")
            return entity
        }

        book.setValue(Set(entities), forKey: "contributors")
    }

    private func replaceBookIdentifiers(_ identifiers: [BookIdentifier], for book: NSManagedObject) {
        relatedObjects(book, "bookIdentifiers").forEach(context.delete)

        let entities = identifiers.map { identifier -> NSManagedObject in
            let entity = makeEntity(named: "BookIdentifierEntity", inStoreOf: book)
            entity.setValue(identifier.type.rawValue, forKey: "type")
            entity.setValue(identifier.value, forKey: "value")
            entity.setValue(book, forKey: "book")
            return entity
        }

        book.setValue(Set(entities), forKey: "bookIdentifiers")
    }

    private func fetchBookEntity(by itemID: UUID) -> NSManagedObject? {
        fetchEntities(
            named: "BookEntity",
            predicate: NSPredicate(format: "item.id == %@", itemID as NSUUID),
            fetchLimit: 1
        ).first
    }
}
