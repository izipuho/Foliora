import CoreData
import Foundation

extension CoreDataDomainMapper {
    static func bellRecord(from entity: NSManagedObject) -> BellRecord {
        guard let itemEntity = entity.value(forKey: "item") as? NSManagedObject else {
            preconditionFailure("BellEntity is missing its ItemEntity relationship.")
        }

        let itemRecord = itemRecord(from: itemEntity)

        return BellRecord(
            item: itemRecord,
            details: BellDetails(
                itemID: itemRecord.id,
                material: bellMaterial(from: stringValue(entity, "material", default: BellMaterial.unknown.rawValue)),
                customMaterialName: entity.value(forKey: "customMaterialName") as? String
            )
        )
    }

    private static func bellMaterial(from rawValue: String) -> BellMaterial {
        BellMaterial(rawValue: rawValue) ?? .unknown
    }
}
