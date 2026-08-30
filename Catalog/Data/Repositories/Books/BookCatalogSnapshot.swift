import CoreData
import Foundation

extension CatalogSnapshot {
    var bookRecords: [BookRecord] {
        itemEntities.compactMap { itemEntity in
            guard let bookEntity = itemEntity.value(forKey: "book") as? NSManagedObject else { return nil }
            return CoreDataDomainMapper.bookRecord(from: bookEntity)
        }
    }

    var bookSeries: [BookSeries] {
        let series = collectionEntities.flatMap { collectionEntity in
            CoreDataDomainMapper.relatedObjects(collectionEntity, "bookSeries")
                .map { CoreDataDomainMapper.bookSeries(from: $0) }
        }
        let uniqueByID = Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var publishers: [Publisher] {
        let publishers = publisherEntities.map { CoreDataDomainMapper.publisher(from: $0) }
        let uniqueByID = Dictionary(publishers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var people: [Person] {
        let people = personEntities.map { CoreDataDomainMapper.person(from: $0) }
        let uniqueByID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var recordsByID: [UUID: BookRecord] {
        Dictionary(uniqueKeysWithValues: bookRecords.map { ($0.id, $0) })
    }
}
