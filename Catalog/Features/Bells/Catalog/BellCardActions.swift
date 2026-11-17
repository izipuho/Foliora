import Foundation

/// Persists bell card-management actions (move, delete, batch edit) for every screen that manages bells.
@MainActor
struct BellCardActions {
    let repository: any AppRepository
    let snapshot: CatalogSnapshot?
    let collection: CollectionSummary?
    let canEdit: Bool

    func saveHome(_ home: Home, locations: [Location]) {
        repository.saveHome(home)
        repository.saveLocations(locations, in: home.id)
    }

    func move(_ bells: [BellCatalogItem], to locationID: UUID?) {
        guard canEdit else { return }

        let storageContext = CatalogStorageContext(snapshot: snapshot, collection: collection)
        let location = storageContext.location(for: locationID)
        for bell in bells {
            guard let record = snapshot?.recordsByID[bell.id] else { continue }
            repository.saveBellRecord(
                record.moving(
                    to: location,
                    storagePath: location.map(storageContext.storagePath(for:))
                )
            )
        }
    }

    func delete(_ bells: [BellCatalogItem]) {
        guard canEdit else { return }

        for bell in bells {
            repository.deleteBellRecord(bellID: bell.id)
        }
    }

    func batchEdit(
        _ bells: [BellCatalogItem],
        itemEdit: ItemBatchEdit,
        bellEdit: BellBatchEdit
    ) {
        guard canEdit else { return }

        let updatedRecords = bells.compactMap { bell -> BellRecord? in
            guard let record = snapshot?.recordsByID[bell.id] else { return nil }
            return BellRecord(
                item: itemEdit.applying(to: record.item),
                details: bellEdit.applying(to: record.details)
            )
        }
        guard !updatedRecords.isEmpty else { return }

        repository.saveBellRecords(updatedRecords)
    }
}
