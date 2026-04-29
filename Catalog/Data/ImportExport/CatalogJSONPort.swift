import Foundation
import SwiftData

enum CatalogJSONPort {
    static func exportArchiveData(from modelContainer: ModelContainer) async throws -> Data {
        let actor = CatalogImportExportActor(modelContainer: modelContainer)
        return try await actor.exportArchiveData()
    }

    static func importArchive(from url: URL, into modelContainer: ModelContainer) async throws -> CatalogImportExportActor.ImportResult {
        let actor = CatalogImportExportActor(modelContainer: modelContainer)
        return try await actor.importArchive(from: url)
    }
}
