import Foundation

/// Identifies the current set of photo assets participating in item recognition.
struct ItemRecognitionMediaSnapshot: Equatable, Sendable {
    let photoAssetIDs: Set<UUID>

    static let empty = ItemRecognitionMediaSnapshot(photoAssetIDs: [])
}
