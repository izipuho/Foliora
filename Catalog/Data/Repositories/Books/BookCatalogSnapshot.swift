import CoreData
import Foundation

extension CatalogSnapshot {
    var bookRecords: [BookRecord] {
        itemEntities.compactMap { itemEntity in
            guard let bookEntity = itemEntity.value(forKey: "book") as? NSManagedObject else { return nil }
            return CoreDataDomainMapper.bookRecord(from: bookEntity)
        }
    }

    var recordsByID: [UUID: BookRecord] {
        Dictionary(uniqueKeysWithValues: bookRecords.map { ($0.id, $0) })
    }
}
