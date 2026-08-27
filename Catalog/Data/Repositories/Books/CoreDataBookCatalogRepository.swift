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
        entity.setValue(book.details.series.map { upsertBookSeries($0, for: item) }, forKey: "series")
        replaceContributors(book.details.contributors, for: entity)
        entity.setValue(item, forKey: "item")
        fillInverseRelationship(from: entity, relationshipName: "item", with: item)

        previousPersons.forEach(deletePersonIfOrphaned)
    }

    private func apply(_ book: BookRecord, to entity: NSManagedObject) {
        entity.setValue(book.details.languageCode, forKey: "languageCode")
        entity.setValue(book.details.pageCount, forKey: "pageCount")
        entity.setValue(book.details.publicationPlaceName, forKey: "publicationPlaceName")
        entity.setValue(book.details.publicationYear, forKey: "publicationYear")
        entity.setValue(book.details.volumeNumber, forKey: "volumeNumber")
        entity.setValue(book.details.publicationPlace.map(upsertBookPlace), forKey: "publicationPlace")
    }

    private func upsertBookSeries(_ series: BookSeries, for item: NSManagedObject) -> NSManagedObject {
        guard let collection = item.value(forKey: "collection") as? NSManagedObject else {
            preconditionFailure("ItemEntity is missing its CollectionEntity relationship while saving BookSeriesEntity.")
        }

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
        entity.setValue(collection, forKey: "collection")
        return entity
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
        return entity
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
