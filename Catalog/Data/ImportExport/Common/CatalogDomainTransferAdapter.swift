import CoreData
import Foundation

/// Defines product-specific import/export behavior used by the common catalog transfer flow.
@MainActor
protocol CatalogDomainTransferAdapter {
    func exportPayloads(
        from context: NSManagedObjectContext,
        itemIDs: Set<UUID>
    ) throws -> [CatalogDomainPayload]

    func filteredPayloads(
        _ payloads: [CatalogDomainPayload],
        itemIDs: Set<UUID>
    ) -> [CatalogDomainPayload]

    func applyPayloads(
        _ payloads: [CatalogDomainPayload],
        itemEntitiesByID: [UUID: NSManagedObject],
        in context: NSManagedObjectContext
    )

    func deleteDomainEntities(in context: NSManagedObjectContext) throws
}
