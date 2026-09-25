import UIKit

extension BookPhotoAnalysisController: ItemCreationRecognitionController {}

extension ItemCreationService {
    struct PreparedBookMedia {
        let coverImage: MediaAsset?
        let mediaAssets: [MediaAsset]
        let didFailToExtractCover: Bool
    }

    struct NormalizedBookPhoto {
        let asset: MediaAsset?
        let analysisImage: UIImage
    }

    @MainActor
    static func prepareBookMedia(
        _ assets: [MediaAsset],
        itemID: UUID
    ) async -> PreparedBookMedia {
        let photos = assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let coverID = photos.first?.id else {
            return PreparedBookMedia(
                coverImage: nil,
                mediaAssets: assets.map { $0.with(itemID: itemID) },
                didFailToExtractCover: false
            )
        }

        var coverImage: MediaAsset?
        var mediaAssets = assets
        var didFailToExtractCover = false

        for source in photos {
            guard let sourceImage = image(for: source) else { continue }

            let isCover = source.id == coverID
            let normalized = await normalizeBookPhoto(
                sourceImage,
                sourceAsset: source,
                itemID: itemID,
                asCover: isCover
            )

            guard let asset = normalized.asset else {
                didFailToExtractCover = didFailToExtractCover || isCover
                continue
            }

            if isCover {
                coverImage = asset
                mediaAssets.removeAll { $0.id == source.id }
            } else if let index = mediaAssets.firstIndex(where: { $0.id == source.id }) {
                mediaAssets[index] = asset
            }
        }

        mediaAssets = mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { $0.element.with(itemID: itemID, sortOrder: $0.offset) }

        return PreparedBookMedia(
            coverImage: coverImage,
            mediaAssets: mediaAssets,
            didFailToExtractCover: didFailToExtractCover
        )
    }

    @MainActor
    static func normalizeBookPhoto(
        _ image: UIImage,
        sourceAsset: MediaAsset,
        itemID: UUID,
        asCover: Bool
    ) async -> NormalizedBookPhoto {
        guard let extracted = await BookCoverExtractor().extractCover(from: image) else {
            return NormalizedBookPhoto(asset: nil, analysisImage: image)
        }

        if !sourceAsset.localIdentifier.isEmpty {
            LocalMediaFileStore.shared.deleteFile(for: sourceAsset.localIdentifier)
        }

        let analysisImage = extracted.originalData.flatMap(UIImage.init(data:)) ?? image
        if asCover {
            return NormalizedBookPhoto(
                asset: extracted.with(
                    itemID: itemID,
                    displayName: String(localized: "editor.media.cover"),
                    sortOrder: 0
                ),
                analysisImage: analysisImage
            )
        }

        let asset = sourceAsset.with(
            itemID: sourceAsset.itemID ?? itemID,
            localIdentifier: ""
        ) { copy in
            copy.fileName = extracted.fileName
            copy.mimeType = extracted.mimeType
            copy.byteSize = extracted.byteSize
            copy.checksum = extracted.checksum
            copy.width = extracted.width
            copy.height = extracted.height
            copy.duration = extracted.duration
            copy.metadataJSON = extracted.metadataJSON
            copy.originalData = extracted.originalData
        }

        return NormalizedBookPhoto(asset: asset, analysisImage: analysisImage)
    }
}
