import Foundation

/// Represents one durable item-level recognition result and its media snapshot.
struct ItemRecognitionRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int16 = 2

    let itemID: UUID
    let photoAssetIDs: Set<UUID>
    let evidenceData: Data?
    let resultData: Data?
    let schemaVersion: Int16
    let updatedAt: Date

    init(
        itemID: UUID,
        photoAssetIDs: Set<UUID>,
        evidenceData: Data?,
        resultData: Data?,
        schemaVersion: Int16 = Self.currentSchemaVersion,
        updatedAt: Date = .now
    ) {
        self.itemID = itemID
        self.photoAssetIDs = photoAssetIDs
        self.evidenceData = evidenceData
        self.resultData = resultData
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
    }
}
