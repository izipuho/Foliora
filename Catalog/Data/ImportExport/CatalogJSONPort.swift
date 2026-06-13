import CoreData
import Foundation

enum CatalogJSONPort {
    @MainActor
    static func exportArchiveData(context: NSManagedObjectContext) async throws -> Data {
        let actor = CatalogImportExportActor(context: context)
        return try actor.exportArchiveData()
    }

    @MainActor
    static func importArchive(
        from url: URL,
        context: NSManagedObjectContext
    ) async throws -> CatalogImportExportActor.ImportResult {
        let actor = CatalogImportExportActor(context: context)
        return try actor.importArchive(from: url)
    }
}
