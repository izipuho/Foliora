import CoreData
import Foundation

extension CoreDataDomainMapper {
    static func bookRecord(from entity: NSManagedObject) -> BookRecord {
        precondition(entity.entity.name == "BookEntity", "CoreDataDomainMapper.bookRecord(from:) expects BookEntity.")

        guard let itemEntity = entity.value(forKey: "item") as? NSManagedObject else {
            preconditionFailure("BookEntity is missing its ItemEntity relationship.")
        }

        let itemRecord = itemRecord(from: itemEntity)
        let publicationPlaceEntity = entity.value(forKey: "publicationPlace") as? NSManagedObject
        let contributors = relatedObjects(entity, "contributors")
            .sorted { intValue($0, "order") < intValue($1, "order") }
            .map(bookContributor)

        return BookRecord(
            item: itemRecord,
            details: BookDetails(
                itemID: itemRecord.id,
                languageCode: entity.value(forKey: "languageCode") as? String,
                pageCount: positiveIntValue(entity, "pageCount"),
                publicationPlaceName: entity.value(forKey: "publicationPlaceName") as? String,
                publicationYear: optionalIntValue(entity, "publicationYear"),
                volumeNumber: positiveIntValue(entity, "volumeNumber"),
                publicationPlace: publicationPlaceEntity.map(place),
                contributors: contributors
            )
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

    private static func positiveIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        guard let value = optionalIntValue(entity, key), value > 0 else { return nil }
        return value
    }
}
