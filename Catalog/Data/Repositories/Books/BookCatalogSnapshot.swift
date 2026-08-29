import CoreData
import Foundation

extension CatalogSnapshot {
    var bookRecords: [BookRecord] {
        itemEntities.compactMap { item in
            guard
                let rawKind = item.value(forKey: "kind") as? String,
                rawKind == CollectionKind.books.rawValue,
                let book = item.value(forKey: "book") as? NSManagedObject
            else {
                return nil
            }

            return CoreDataDomainMapper.bookRecord(from: book)
        }
    }

    var bookSeries: [BookSeries] {
        collectionEntities.flatMap { collection in
            let series: [NSManagedObject]
            if let values = collection.value(forKey: "bookSeries") as? Set<NSManagedObject> {
                series = Array(values)
            } else {
                series = (collection.value(forKey: "bookSeries") as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
            }

            return series.map { CoreDataDomainMapper.bookSeries(from: $0) }
        }
    }

    var publishers: [Publisher] {
        publisherEntities
            .map { CoreDataDomainMapper.publisher(from: $0) }
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var bookRecordsByID: [UUID: BookRecord] {
        Dictionary(uniqueKeysWithValues: bookRecords.map { ($0.id, $0) })
    }
}
