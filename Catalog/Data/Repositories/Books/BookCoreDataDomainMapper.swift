import CoreData
import Foundation

extension CoreDataDomainMapper {
    static func bookRecord(from entity: NSManagedObject, includesMediaData: Bool = true) -> BookRecord {
        precondition(entity.entity.name == "BookEntity", "CoreDataDomainMapper.bookRecord(from:) expects BookEntity.")

        guard let itemEntity = entity.value(forKey: "item") as? NSManagedObject else {
            preconditionFailure("BookEntity is missing its ItemEntity relationship.")
        }

        let itemRecord = itemRecord(from: itemEntity, includesMediaData: includesMediaData)
        let coverImageEntity = entity.value(forKey: "coverImage") as? NSManagedObject
        let publisherEntity = entity.value(forKey: "publisher") as? NSManagedObject
        let seriesEntity = entity.value(forKey: "series") as? NSManagedObject
        let contributors = relatedObjects(entity, "contributors")
            .sorted { intValue($0, "order") < intValue($1, "order") }
            .compactMap { bookContributor(from: $0, includesMediaData: includesMediaData) }
        let identifiers = relatedObjects(entity, "bookIdentifiers")
            .map { bookIdentifier(from: $0) }
            .sorted {
                if $0.type.rawValue == $1.type.rawValue {
                    return $0.value < $1.value
                }
                return $0.type.rawValue < $1.type.rawValue
            }

        return BookRecord(
            item: itemRecord,
            details: BookDetails(
                itemID: itemRecord.id,
                subtitle: entity.value(forKey: "subtitle") as? String,
                languageCode: entity.value(forKey: "languageCode") as? String,
                genre: entity.value(forKey: "genre") as? String,
                pageCount: positiveIntValue(entity, "pageCount"),
                publicationYear: optionalIntValue(entity, "publicationYear"),
                volumeNumber: positiveIntValue(entity, "volumeNumber"),
                coverImage: coverImageEntity.map { mediaAsset(from: $0, includesMediaData: includesMediaData) },
                publisher: publisherEntity.flatMap { publisher(from: $0, includesMediaData: includesMediaData) },
                contributors: contributors,
                series: seriesEntity.flatMap { bookSeries(from: $0, includesMediaData: includesMediaData) },
                identifiers: identifiers
            )
        )
    }

    /// Maps a series, or returns `nil` while CloudKit has not linked it to its collection.
    static func bookSeries(from entity: NSManagedObject, includesMediaData: Bool = true) -> BookSeries? {
        precondition(
            entity.entity.name == "BookSeriesEntity",
            "CoreDataDomainMapper.bookSeries(from:) expects BookSeriesEntity."
        )

        guard let collectionEntity = entity.value(forKey: "collection") as? NSManagedObject else {
            logUnlinkedReference(entity, missing: "collection")
            return nil
        }

        let publisherEntity = entity.value(forKey: "publisher") as? NSManagedObject

        return BookSeries(
            id: uuidValue(entity, "id"),
            collectionID: uuidValue(collectionEntity, "id"),
            name: stringValue(entity, "name"),
            totalBookCount: optionalIntValue(entity, "totalBookCount"),
            publisher: publisherEntity.flatMap { publisher(from: $0, includesMediaData: includesMediaData) }
        )
    }

    /// Maps a publisher, or returns `nil` while CloudKit has not linked it to its collection.
    static func publisher(from entity: NSManagedObject, includesMediaData: Bool = true) -> Publisher? {
        precondition(
            entity.entity.name == "PublisherEntity",
            "CoreDataDomainMapper.publisher(from:) expects PublisherEntity."
        )

        let id = uuidValue(entity, "id")
        guard let collectionEntity = entity.value(forKey: "collection") as? NSManagedObject else {
            logUnlinkedReference(entity, missing: "collection")
            return nil
        }

        let logoEntity = entity.value(forKey: "logo") as? NSManagedObject

        return Publisher(
            id: id,
            canonicalID: entity.value(forKey: "canonicalID") as? UUID ?? id,
            collectionID: uuidValue(collectionEntity, "id"),
            name: stringValue(entity, "name"),
            logo: logoEntity.map { mediaAsset(from: $0, includesMediaData: includesMediaData) }
        )
    }

    /// Maps a contributor, or returns `nil` while CloudKit has not linked its person.
    private static func bookContributor(from entity: NSManagedObject, includesMediaData: Bool) -> BookContributor? {
        precondition(
            entity.entity.name == "BookContributorEntity",
            "CoreDataDomainMapper.bookContributor(from:) expects BookContributorEntity."
        )

        guard let personEntity = entity.value(forKey: "person") as? NSManagedObject,
              let person = person(from: personEntity, includesMediaData: includesMediaData)
        else {
            logUnlinkedReference(entity, missing: "person")
            return nil
        }

        let rawRole = stringValue(entity, "role")
        guard let role = BookContributorRole(rawValue: rawRole) else {
            preconditionFailure("BookContributorEntity has unsupported role: \(rawRole).")
        }

        return BookContributor(
            role: role,
            order: intValue(entity, "order"),
            person: person
        )
    }

    private static func bookIdentifier(from entity: NSManagedObject) -> BookIdentifier {
        precondition(
            entity.entity.name == "BookIdentifierEntity",
            "CoreDataDomainMapper.bookIdentifier(from:) expects BookIdentifierEntity."
        )

        let rawType = stringValue(entity, "type")
        guard let type = BookIdentifierType(rawValue: rawType) else {
            preconditionFailure("BookIdentifierEntity has unsupported type: \(rawType).")
        }

        return BookIdentifier(
            type: type,
            value: stringValue(entity, "value")
        )
    }

    private static func positiveIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        guard let value = optionalIntValue(entity, key), value > 0 else { return nil }
        return value
    }
}
