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
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
        request.predicate = NSPredicate(format: "id == %@", series.collectionID as NSUUID)
        request.fetchLimit = 1

        guard let collection = (try? context.fetch(request))?.first else {
            preconditionFailure("BookSeries collection does not exist.")
        }

        _ = upsertBookSeries(series, forCollection: collection)
        saveContext()
    }

    func deleteBookSeries(seriesID: UUID) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BookSeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", seriesID as NSUUID)
        request.fetchLimit = 1

        guard let seriesEntity = (try? context.fetch(request))?.first else { return }

        let booksRequest = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
        booksRequest.predicate = NSPredicate(format: "series == %@", seriesEntity)
        let books = (try? context.fetch(booksRequest)) ?? []

        for book in books {
            book.setValue(nil, forKey: "series")
            book.setValue(nil, forKey: "volumeNumber")
        }

        context.delete(seriesEntity)
        saveContext()
    }

    func savePublisher(_ publisher: Publisher) {
        _ = upsertPublisher(publisher)
        saveContext()
    }

    func deletePublisher(publisherID: UUID) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PublisherEntity")
        request.predicate = NSPredicate(format: "id == %@", publisherID as NSUUID)
        let publishers = (try? context.fetch(request)) ?? []
        guard !publishers.isEmpty else { return }

        for publisher in publishers {
            bookRelatedObjects(publisher, "books").forEach {
                $0.setValue(nil, forKey: "publisher")
            }
            bookRelatedObjects(publisher, "bookSeries").forEach {
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
        let persons = bookRelatedObjects(entity, "contributors").compactMap {
            $0.value(forKey: "person") as? NSManagedObject
        }
        guard let item = entity.value(forKey: "item") as? NSManagedObject else { return }

        context.delete(item)
        persons.forEach(deletePersonIfOrphaned)
        deleteOrphanItemTags()
        saveContext()
    }

    private func saveBookRecordWithoutSavingContext(_ book: BookRecord) {
        guard let item = saveItemRecordWithoutSavingContext(book.item) else { return }

        let entity = fetchBookEntity(by: book.id) ?? makeEntity(named: "BookEntity")
        let previousPersons = bookRelatedObjects(entity, "contributors").compactMap {
            $0.value(forKey: "person") as? NSManagedObject
        }

        apply(book, to: entity)
        entity.setValue(book.details.publisher.map(upsertPublisher), forKey: "publisher")
        entity.setValue(book.details.series.map { upsertBookSeries($0, for: item) }, forKey: "series")
        replaceContributors(book.details.contributors, for: entity)
        replaceBookIdentifiers(book.details.identifiers, for: entity)
        entity.setValue(item, forKey: "item")
        fillInverseRelationship(from: entity, relationshipName: "item", with: item)

        previousPersons.forEach(deletePersonIfOrphaned)
    }

    private func apply(_ book: BookRecord, to entity: NSManagedObject) {
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

        let request = NSFetchRequest<NSManagedObject>(entityName: "BookSeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", series.id as NSUUID)
        request.fetchLimit = 1

        let existingEntity = (try? context.fetch(request))?.first
        if let existingCollection = existingEntity?.value(forKey: "collection") as? NSManagedObject,
           existingCollection != collection {
            preconditionFailure("BookSeriesEntity cannot be shared across collections.")
        }

        let entity = existingEntity ?? makeEntity(named: "BookSeriesEntity")
        if existingEntity == nil,
           let store = collection.objectID.persistentStore {
            context.assign(entity, to: store)
        }

        entity.setValue(series.id, forKey: "id")
        entity.setValue(series.name, forKey: "name")
        entity.setValue(series.totalBookCount, forKey: "totalBookCount")
        entity.setValue(series.publisher.map(upsertPublisher), forKey: "publisher")
        entity.setValue(collection, forKey: "collection")
        return entity
    }

    private func upsertPublisher(_ publisher: Publisher) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PublisherEntity")
        request.predicate = NSPredicate(format: "id == %@", publisher.id as NSUUID)
        request.fetchLimit = 1

        let entity = (try? context.fetch(request))?.first ?? makeEntity(named: "PublisherEntity")
        entity.setValue(publisher.id, forKey: "id")
        entity.setValue(publisher.name, forKey: "name")
        entity.setValue(publisher.location.map(upsertBookPlace), forKey: "location")
        replacePublisherLogo(publisher.logo, for: entity)
        return entity
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

        applyReferenceMediaAsset(logo.with(sortOrder: 0), to: logoEntity)
        logoEntity.setValue(publisher, forKey: "publisher")
        publisher.setValue(logoEntity, forKey: "logo")
    }

    private func replaceContributors(_ contributors: [BookContributor], for book: NSManagedObject) {
        bookRelatedObjects(book, "contributors").forEach(context.delete)

        let entities = contributors.map { contributor -> NSManagedObject in
            let entity = makeEntity(named: "BookContributorEntity")
            entity.setValue(contributor.role.rawValue, forKey: "role")
            entity.setValue(contributor.order, forKey: "order")
            entity.setValue(book, forKey: "book")
            entity.setValue(upsertPerson(contributor.person), forKey: "person")
            return entity
        }

        book.setValue(Set(entities), forKey: "contributors")
    }

    private func replaceBookIdentifiers(_ identifiers: [BookIdentifier], for book: NSManagedObject) {
        bookRelatedObjects(book, "bookIdentifiers").forEach(context.delete)

        let entities = identifiers.map { identifier -> NSManagedObject in
            let entity = makeEntity(named: "BookIdentifierEntity")
            entity.setValue(identifier.type.rawValue, forKey: "type")
            entity.setValue(identifier.value, forKey: "value")
            entity.setValue(book, forKey: "book")
            return entity
        }

        book.setValue(Set(entities), forKey: "bookIdentifiers")
    }

    private func upsertPerson(_ person: Person) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PersonEntity")
        request.predicate = NSPredicate(format: "id == %@", person.id as NSUUID)
        request.fetchLimit = 1

        let entity = (try? context.fetch(request))?.first ?? makeEntity(named: "PersonEntity")
        entity.setValue(person.id, forKey: "id")
        entity.setValue(person.name, forKey: "name")
        entity.setValue(person.birthYear, forKey: "birthYear")
        entity.setValue(person.deathYear, forKey: "deathYear")
        entity.setValue(person.biography, forKey: "biography")
        entity.setValue(person.birthPlace.map(upsertBookPlace), forKey: "birthPlace")
        entity.setValue(person.deathPlace.map(upsertBookPlace), forKey: "deathPlace")
        replaceReferenceMediaAssets(
            person.photos,
            relationshipName: "photos",
            inverseRelationshipName: "person",
            for: entity
        )
        return entity
    }

    private func replaceReferenceMediaAssets(
        _ mediaAssets: [MediaAsset],
        relationshipName: String,
        inverseRelationshipName: String,
        for owner: NSManagedObject
    ) {
        let existingAssets = Set(bookRelatedObjects(owner, relationshipName))
        let incomingIDs = Set(mediaAssets.map(\.id))
        var existingByID: [UUID: NSManagedObject] = [:]

        for entity in existingAssets {
            guard let id = entity.value(forKey: "id") as? UUID else { continue }
            existingByID[id] = entity
        }

        let updatedAssets = mediaAssets.map { asset -> NSManagedObject in
            let entity = existingByID[asset.id] ?? makeEntity(named: "MediaAssetEntity")
            if entity.objectID.persistentStore == nil,
               let store = owner.objectID.persistentStore {
                context.assign(entity, to: store)
            }
            applyReferenceMediaAsset(asset, to: entity)
            entity.setValue(owner, forKey: inverseRelationshipName)
            return entity
        }

        for entity in existingAssets {
            guard
                let id = entity.value(forKey: "id") as? UUID,
                !incomingIDs.contains(id)
            else {
                continue
            }
            context.delete(entity)
        }

        owner.setValue(Set(updatedAssets), forKey: relationshipName)
    }

    private func applyReferenceMediaAsset(_ asset: MediaAsset, to entity: NSManagedObject) {
        let isNewEntity = entity.value(forKey: "id") == nil
        let existingChecksum = entity.value(forKey: "checksum") as? String
        let shouldUpdateOriginalData = isNewEntity || existingChecksum != asset.checksum

        entity.setValue(asset.id, forKey: "id")
        entity.setValue(asset.kind.rawValue, forKey: "kind")
        entity.setValue(asset.localIdentifier, forKey: "localIdentifier")
        entity.setValue(asset.displayName, forKey: "displayName")
        entity.setValue(asset.sortOrder, forKey: "sortOrder")
        entity.setValue(asset.fileName, forKey: "fileName")
        entity.setValue(asset.mimeType, forKey: "mimeType")
        entity.setValue(asset.byteSize, forKey: "byteSize")
        entity.setValue(asset.checksum, forKey: "checksum")
        entity.setValue(asset.width, forKey: "width")
        entity.setValue(asset.height, forKey: "height")
        entity.setValue(asset.duration, forKey: "duration")
        entity.setValue(asset.metadataJSON, forKey: "metadataJSON")
        if shouldUpdateOriginalData {
            entity.setValue(asset.originalData, forKey: "originalData")
        }
    }

    private func deletePersonIfOrphaned(_ person: NSManagedObject) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BookContributorEntity")
        request.predicate = NSPredicate(format: "person == %@", person)
        request.fetchLimit = 1

        let hasRemainingContribution = (try? context.fetch(request))?.contains(where: { !$0.isDeleted }) == true
        guard !hasRemainingContribution else { return }
        context.delete(person)
    }

    private func fetchBookEntity(by itemID: UUID) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
        request.predicate = NSPredicate(format: "item.id == %@", itemID as NSUUID)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private func upsertBookPlace(_ place: Place) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PlaceEntity")
        request.predicate = NSPredicate(format: "id == %@", place.id as NSUUID)
        request.fetchLimit = 1

        let entity = (try? context.fetch(request))?.first ?? makeEntity(named: "PlaceEntity")
        entity.setValue(place.id, forKey: "id")
        entity.setValue(place.displayName, forKey: "displayName")
        entity.setValue(place.countryCode, forKey: "countryCode")
        entity.setValue(place.countryName, forKey: "countryName")
        entity.setValue(place.regionName, forKey: "regionName")
        entity.setValue(place.cityName, forKey: "cityName")
        entity.setValue(place.latitude, forKey: "latitude")
        entity.setValue(place.longitude, forKey: "longitude")
        return entity
    }

    private func bookRelatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }
}
