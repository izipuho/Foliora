import Foundation

struct MediaAsset: Identifiable, Hashable, Codable {
    let id: UUID
    let itemID: UUID
    var kind: MediaKind
    var localIdentifier: String
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
            return "Photo"
        case .document:
            return "Document"
        case .model3D:
            return "3D Model"
        }
    }
}
