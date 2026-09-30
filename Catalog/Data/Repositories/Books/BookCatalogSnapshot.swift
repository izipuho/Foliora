import CoreData
import Foundation

/// Book records and references held by `CatalogSnapshot`, mapped once per load.
struct CatalogRecords {
    let bookRecords: [BookRecord]
    let recordsByID: [UUID: BookRecord]
    let bookSeries: [BookSeries]
    let publishers: [Publisher]
    let people: [Person]

    nonisolated init() {
        bookRecords = []
        recordsByID = [:]
        bookSeries = []
        publishers = []
        people = []
    }

    /// Maps book records and references without media bytes.
    nonisolated init(
        itemEntities: [NSManagedObject],
        collectionEntities: [NSManagedObject],
        publisherEntities: [NSManagedObject],
        personEntities: [NSManagedObject]
    ) {
        bookRecords = itemEntities.compactMap { itemEntity in
            guard let bookEntity = itemEntity.value(forKey: "book") as? NSManagedObject else { return nil }
            return CoreDataDomainMapper.bookRecord(from: bookEntity, includesMediaData: false)
        }
        recordsByID = Dictionary(uniqueKeysWithValues: bookRecords.map { ($0.id, $0) })
        bookSeries = Self.uniqueSortedByName(
            collectionEntities.flatMap { collectionEntity in
                CoreDataDomainMapper.relatedObjects(collectionEntity, "bookSeries")
                    .map { CoreDataDomainMapper.bookSeries(from: $0, includesMediaData: false) }
            },
            name: \.name
        )
        publishers = Self.uniqueSortedByName(
            publisherEntities.map { CoreDataDomainMapper.publisher(from: $0, includesMediaData: false) },
            name: \.name
        )
        people = Self.uniqueSortedByName(
            personEntities.map { CoreDataDomainMapper.person(from: $0, includesMediaData: false) },
            name: \.sortName
        )
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

extension CatalogSnapshot {
    var bookRecords: [BookRecord] { records.bookRecords }
    var recordsByID: [UUID: BookRecord] { records.recordsByID }
    var bookSeries: [BookSeries] { records.bookSeries }
    var publishers: [Publisher] { records.publishers }
    var people: [Person] { records.people }
}
