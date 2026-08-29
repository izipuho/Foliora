import CoreData
import Foundation

extension CoreDataDomainMapper {
    static func bookRecord(from entity: NSManagedObject) -> BookRecord {
        precondition(entity.entity.name == "BookEntity", "CoreDataDomainMapper.bookRecord(from:) expects BookEntity.")

        guard let itemEntity = entity.value(forKey: "item") as? NSManagedObject else {
            preconditionFailure("BookEntity is missing its ItemEntity relationship.")
        }

        let itemRecord = itemRecord(from: itemEntity)
        let publisherEntity = entity.value(forKey: "publisher") as? NSManagedObject
        let seriesEntity = entity.value(forKey: "series") as? NSManagedObject
        let contributors = relatedObjects(entity, "contributors")
            .sorted { intValue($0, "order") < intValue($1, "order") }
            .map { bookContributor(from: $0) }
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
                languageCode: entity.value(forKey: "languageCode") as? String,
                genre: entity.value(forKey: "genre") as? String,
                pageCount: positiveIntValue(entity, "pageCount"),
                publicationYear: optionalIntValue(entity, "publicationYear"),
                volumeNumber: positiveIntValue(entity, "volumeNumber"),
                publisher: publisherEntity.map { publisher(from: $0) },
                contributors: contributors,
                series: seriesEntity.map { bookSeries(from: $0) },
                identifiers: identifiers
            )
        )
    }

    static func bookSeries(from entity: NSManagedObject) -> BookSeries {
        precondition(
            entity.entity.name == "BookSeriesEntity",
            "CoreDataDomainMapper.bookSeries(from:) expects BookSeriesEntity."
        )

        guard let collectionEntity = entity.value(forKey: "collection") as? NSManagedObject else {
            preconditionFailure("BookSeriesEntity is missing its CollectionEntity relationship.")
        }

        let publisherEntity = entity.value(forKey: "publisher") as? NSManagedObject

        return BookSeries(
            id: uuidValue(entity, "id"),
            collectionID: uuidValue(collectionEntity, "id"),
            name: stringValue(entity, "name"),
            totalBookCount: optionalIntValue(entity, "totalBookCount"),
            publisher: publisherEntity.map { publisher(from: $0) }
        )
    }

    static func publisher(from entity: NSManagedObject) -> Publisher {
        precondition(
            entity.entity.name == "PublisherEntity",
            "CoreDataDomainMapper.publisher(from:) expects PublisherEntity."
        )

        let locationEntity = entity.value(forKey: "location") as? NSManagedObject
        let logoEntity = entity.value(forKey: "logo") as? NSManagedObject

        return Publisher(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            location: locationEntity.map { place(from: $0) },
            logo: logoEntity.map { mediaAsset(from: $0) }
        )
    }

    private static func bookContributor(from entity: NSManagedObject) -> BookContributor {
        precondition(
            entity.entity.name == "BookContributorEntity",
            "CoreDataDomainMapper.bookContributor(from:) expects BookContributorEntity."
        )

        guard let personEntity = entity.value(forKey: "person") as? NSManagedObject else {
            preconditionFailure("BookContributorEntity is missing its PersonEntity relationship.")
        }

        let rawRole = stringValue(entity, "role")
        guard let role = BookContributorRole(rawValue: rawRole) else {
            preconditionFailure("BookContributorEntity has unsupported role: \(rawRole).")
        }

        return BookContributor(
            role: role,
            order: intValue(entity, "order"),
            person: person(from: personEntity)
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
