import Foundation

struct MediaAsset: Identifiable, Hashable, Codable {
    let id: UUID
    let itemID: UUID
    var kind: MediaKind
    var localIdentifier: String
    var displayName: String?
    var sortOrder: Int
    var fileName: String? = nil
    var mimeType: String? = nil
    var byteSize: Int? = nil
    var checksum: String? = nil
    var width: Int? = nil
    var height: Int? = nil
    var duration: Double? = nil
    var metadataJSON: String? = nil
    var thumbnailData: Data? = nil
    var originalData: Data? = nil

    func with(
        itemID: UUID? = nil,
        kind: MediaKind? = nil,
        localIdentifier: String? = nil,
        displayName: String? = nil,
        sortOrder: Int? = nil,
        update: (inout MediaAsset) -> Void = { _ in }
    ) -> MediaAsset {
        var copy = MediaAsset(
            id: id,
            itemID: itemID ?? self.itemID,
            kind: kind ?? self.kind,
            localIdentifier: localIdentifier ?? self.localIdentifier,
            displayName: displayName ?? self.displayName,
            sortOrder: sortOrder ?? self.sortOrder,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: byteSize,
            checksum: checksum,
            width: width,
            height: height,
            duration: duration,
            metadataJSON: metadataJSON,
            thumbnailData: thumbnailData,
            originalData: originalData
        )
        update(&copy)
        return copy
    }
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
