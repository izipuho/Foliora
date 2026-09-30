import CoreData
import Foundation

extension CatalogSnapshot {
    var recordsByID: [UUID: BookRecord] {
        bookRecordsByID
    }

    /// Maps book records once per snapshot load. Media is mapped without `originalData`.
    nonisolated static func mapBookRecords(from itemEntities: [NSManagedObject]) -> [BookRecord] {
        itemEntities.compactMap { itemEntity in
            guard let bookEntity = itemEntity.value(forKey: "book") as? NSManagedObject else { return nil }
            return CoreDataDomainMapper.bookRecord(from: bookEntity, includesMediaData: false)
        }
    }

    nonisolated static func mapBookSeries(from collectionEntities: [NSManagedObject]) -> [BookSeries] {
        let series = collectionEntities.flatMap { collectionEntity in
            CoreDataDomainMapper.relatedObjects(collectionEntity, "bookSeries")
                .map { CoreDataDomainMapper.bookSeries(from: $0, includesMediaData: false) }
        }
        return uniqueSortedByName(series, name: \.name)
    }

    nonisolated static func mapPublishers(from publisherEntities: [NSManagedObject]) -> [Publisher] {
        let publishers = publisherEntities.map { CoreDataDomainMapper.publisher(from: $0, includesMediaData: false) }
        return uniqueSortedByName(publishers, name: \.name)
    }

    nonisolated static func mapPeople(from personEntities: [NSManagedObject]) -> [Person] {
        let people = personEntities.map { CoreDataDomainMapper.person(from: $0, includesMediaData: false) }
        return uniqueSortedByName(people, name: \.sortName)
    }

    /// Keeps the first value per ID and sorts by name, then by ID for a stable order.
    nonisolated private static func uniqueSortedByName<Value: Identifiable>(
        _ values: [Value],
        name: (Value) -> String
    ) -> [Value] where Value.ID == UUID {
        let uniqueByID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return uniqueByID.values.sorted {
            let comparison = name($0).localizedCaseInsensitiveCompare(name($1))
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
