import CoreData
import Foundation

extension CoreDataCatalogRepository: BellCatalogRepository {
    func saveBellRecord(_ bell: BellRecord) {
        saveBellRecordWithoutSavingContext(bell)
        saveContext()
    }

    func saveBellRecords(_ bells: [BellRecord]) {
        bells.forEach(saveBellRecordWithoutSavingContext)
        saveContext()
    }

    func deleteBellRecord(bellID: UUID) {
        guard let entity = fetchBellEntity(by: bellID) else { return }
        guard let item = entity.value(forKey: "item") as? NSManagedObject else { return }
        context.delete(item)
        deleteOrphanItemTags()
        saveContext()
    }

    private func apply(_ bell: BellRecord, to entity: NSManagedObject) {
        entity.setValue(bell.details.material.rawValue, forKey: "material")
        entity.setValue(bell.details.customMaterialName, forKey: "customMaterialName")
    }

    private func saveBellRecordWithoutSavingContext(_ bell: BellRecord) {
        guard let item = saveItemRecordWithoutSavingContext(bell.item) else { return }

        let entity = fetchBellEntity(by: bell.id) ?? makeEntity(named: "BellEntity")
        apply(bell, to: entity)
        entity.setValue(item, forKey: "item")
        fillInverseRelationship(from: entity, relationshipName: "item", with: item)
    }
}
