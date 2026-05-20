import Foundation

public enum CollectionDomain {}

public struct MediaAsset: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public var kind: MediaKind
    public var localIdentifier: String
    public var displayName: String?
    public var sortOrder: Int

    public init(
        id: UUID,
        itemID: UUID,
        kind: MediaKind,
        localIdentifier: String,
        displayName: String?,
        sortOrder: Int
    ) {
        self.id = id
        self.itemID = itemID
        self.kind = kind
        self.localIdentifier = localIdentifier
        self.displayName = displayName
        self.sortOrder = sortOrder
    }
}

public enum MediaKind: String, CaseIterable, Hashable, Identifiable, Codable, Sendable {
    case photo
    case document
    case model3D

    public var id: String { rawValue }

    public var displayName: String {
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
