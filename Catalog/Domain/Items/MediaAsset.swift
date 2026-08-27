import Foundation

/// Represents media asset data and behavior.
struct MediaAsset: Identifiable, Hashable, Codable {
    let id: UUID
    let itemID: UUID?
    var kind: MediaKind
    var localIdentifier: String
    var displayName: String?
    var sortOrder: Int
    var fileName: String?
    var mimeType: String?
    var byteSize: Int?
    var checksum: String?
    var width: Int?
    var height: Int?
    var duration: Double?
    var metadataJSON: String?
    var originalData: Data?

    init(
        id: UUID,
        itemID: UUID? = nil,
        kind: MediaKind,
        localIdentifier: String,
        displayName: String?,
        sortOrder: Int,
        fileName: String? = nil,
        mimeType: String? = nil,
        byteSize: Int? = nil,
        checksum: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil,
        metadataJSON: String? = nil,
        originalData: Data? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.kind = kind
        self.localIdentifier = localIdentifier
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.checksum = checksum
        self.width = width
        self.height = height
        self.duration = duration
        self.metadataJSON = metadataJSON
        self.originalData = originalData
    }

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
            originalData: originalData
        )
        update(&copy)
        return copy
    }
}

/// Defines the supported media kind values.
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
