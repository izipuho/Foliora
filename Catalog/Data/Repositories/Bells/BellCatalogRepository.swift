import Foundation

/// Defines the bell-specific repository operations.
@MainActor
protocol BellCatalogRepository {
    func saveBellRecord(_ bell: BellRecord)
    func saveBellRecords(_ bells: [BellRecord])
    func deleteBellRecord(bellID: UUID)
}

extension BellCatalogRepository {
    func saveBellRecords(_ bells: [BellRecord]) {
        bells.forEach(saveBellRecord)
    }
}
