import CoreData
import Foundation

extension CoreDataCatalogRepository {
    func itemRecognition(for itemID: UUID) -> ItemRecognitionRecord? {
        guard let item = fetchEntity(named: "ItemEntity", by: itemID),
              let recognition = item.value(forKey: "recognition") as? NSManagedObject,
              let photoAssetIDsData = recognition.value(forKey: "photoAssetIDsData") as? Data,
              let photoAssetIDs = decodeRecognitionPhotoAssetIDs(photoAssetIDsData),
              let updatedAt = recognition.value(forKey: "updatedAt") as? Date else {
            return nil
        }

        let schemaVersion = (recognition.value(forKey: "schemaVersion") as? NSNumber)?.int16Value ?? 0

        return ItemRecognitionRecord(
            itemID: itemID,
            photoAssetIDs: photoAssetIDs,
            evidenceData: recognition.value(forKey: "evidenceData") as? Data,
            resultData: recognition.value(forKey: "resultData") as? Data,
            schemaVersion: schemaVersion,
            updatedAt: updatedAt
        )
    }

    @discardableResult
    func saveItemRecognition(_ record: ItemRecognitionRecord) -> Bool {
        guard let item = fetchEntity(named: "ItemEntity", by: record.itemID),
              let store = item.objectID.persistentStore,
              let photoAssetIDsData = encodeRecognitionPhotoAssetIDs(record.photoAssetIDs) else {
            return false
        }

        let existingRecognition = item.value(forKey: "recognition") as? NSManagedObject
        let recognition = existingRecognition ?? makeEntity(named: "ItemRecognitionEntity")

        if recognition.objectID.persistentStore == nil {
            context.assign(recognition, to: store)
        }

        recognition.setValue(photoAssetIDsData, forKey: "photoAssetIDsData")
        recognition.setValue(record.evidenceData, forKey: "evidenceData")
        recognition.setValue(record.resultData, forKey: "resultData")
        recognition.setValue(record.schemaVersion, forKey: "schemaVersion")
        recognition.setValue(record.updatedAt, forKey: "updatedAt")
        recognition.setValue(item, forKey: "item")

        saveContext()
        return true
    }

    func deleteItemRecognition(for itemID: UUID) {
        guard let item = fetchEntity(named: "ItemEntity", by: itemID),
              let recognition = item.value(forKey: "recognition") as? NSManagedObject else {
            return
        }

        context.delete(recognition)
        saveContext()
    }

    private func encodeRecognitionPhotoAssetIDs(_ ids: Set<UUID>) -> Data? {
        let orderedIDs = ids.sorted { $0.uuidString < $1.uuidString }
        return try? JSONEncoder().encode(orderedIDs)
    }

    private func decodeRecognitionPhotoAssetIDs(_ data: Data) -> Set<UUID>? {
        guard let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return nil
        }
        return Set(ids)
    }
}
