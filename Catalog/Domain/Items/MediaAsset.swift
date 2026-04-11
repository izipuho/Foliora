import Foundation

struct MediaAsset: Identifiable, Hashable {
    let id: UUID
    let itemID: UUID
    var kind: MediaKind
    var localIdentifier: String
    var sortOrder: Int
}

enum MediaKind: String, CaseIterable, Hashable, Identifiable {
    case photo
    case document
    case model3D

    var id: String { rawValue }
}
