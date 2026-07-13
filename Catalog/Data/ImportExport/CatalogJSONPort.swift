import CoreData
import Foundation

enum CatalogJSONPort {
    @MainActor
    static func exportArchiveData(
        context: NSManagedObjectContext,
        selection: CatalogExportSelection
    ) async throws -> Data {
        let actor = CatalogImportExportActor(context: context)
        return try actor.exportArchiveData(selection: selection)
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
