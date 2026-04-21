import Foundation
import SwiftData

enum CatalogJSONPort {
    static func exportData(from modelContainer: ModelContainer) async throws -> Data {
        let actor = CatalogImportExportActor(modelContainer: modelContainer)
        return try await actor.exportData()
    }

    static func `import`(data: Data, into modelContainer: ModelContainer) async throws {
        let actor = CatalogImportExportActor(modelContainer: modelContainer)
        try await actor.importData(data)
    }
}
