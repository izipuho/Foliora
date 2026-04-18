import Foundation

struct MediaAsset: Identifiable, Hashable, Codable {
    let id: UUID
    let itemID: UUID
    var kind: MediaKind
    var localIdentifier: String
    var displayName: String?
    var sortOrder: Int
}

enum MediaKind: String, CaseIterable, Hashable, Identifiable, Codable {
    case photo
    case document
    case model3D

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo:
            return String(localized: "enum.media_kind.photo")
        case .document:
            return String(localized: "enum.media_kind.document")
        case .model3D:
            return String(localized: "enum.media_kind.model3d")
        }
    }
}
