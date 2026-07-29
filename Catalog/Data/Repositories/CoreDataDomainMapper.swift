import CoreData
import Foundation

/// Converts Core Data objects into domain models.
///
/// Centralizes all Core Data → domain mapping used by repositories,
/// snapshot loaders, and import/export.
enum CoreDataDomainMapper {
    static func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    static func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    static func intValue(_ entity: NSManagedObject, _ key: String) -> Int {
        optionalIntValue(entity, key) ?? 0
    }

    static func optionalIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        if let value = entity.value(forKey: key) as? Int {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.intValue
    }

    static func dateValue(_ entity: NSManagedObject, _ key: String) -> Date {
        entity.value(forKey: key) as? Date ?? Date()
    }

    static func doubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }
}
