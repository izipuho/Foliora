import UIKit

extension ItemCreationService {
    @MainActor
    static func prepareBookMedia(
        _ assets: [MediaAsset],
        itemID: UUID
    ) async -> (coverImage: MediaAsset?, mediaAssets: [MediaAsset], usedOriginalCover: Bool) {
        let photos = assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let coverID = photos.first?.id else {
            return (
                coverImage: nil,
                mediaAssets: assets.map { $0.with(itemID: itemID) },
                usedOriginalCover: false
            )
        }

        var coverImage: MediaAsset?
        var mediaAssets = assets
        var usedOriginalCover = false

        for source in photos {
            guard let sourceImage = image(for: source) else { continue }

            let isCover = source.id == coverID
            let normalized = await normalizeBookPhoto(
                sourceImage,
                sourceAsset: source,
                itemID: itemID,
                asCover: isCover
            )

            let asset = normalized.asset

            if isCover {
                usedOriginalCover = !normalized.didExtract

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

        return (
            coverImage: coverImage,
            mediaAssets: mediaAssets,
            usedOriginalCover: usedOriginalCover
        )
    }

    static func makeOriginalBookCover(
        _ image: UIImage,
        itemID: UUID
    ) -> MediaAsset? {
        guard let media = try? ImageMediaBuilder(store: .shared).build(from: image) else {
            return nil
        }

        return media.asset.with(
            itemID: itemID,
            displayName: String(localized: "editor.media.cover"),
            sortOrder: 0
        )
    }

    @MainActor
    static func normalizeBookPhoto(
        _ image: UIImage,
        sourceAsset: MediaAsset,
        itemID: UUID,
        asCover: Bool
    ) async -> (asset: MediaAsset, analysisImage: UIImage, didExtract: Bool) {
        guard let extracted = await BookCoverExtractor().extractCover(from: image) else {
            if asCover,
               let dedicatedCover = makeOriginalBookCover(image, itemID: itemID) {
                if !sourceAsset.localIdentifier.isEmpty {
                    LocalMediaFileStore.shared.deleteFile(for: sourceAsset.localIdentifier)
                }

                return (
                    asset: dedicatedCover,
                    analysisImage: image,
                    didExtract: false
                )
            }

            return (
                asset: sourceAsset.with(
                    itemID: itemID,
                    displayName: asCover ? String(localized: "editor.media.cover") : sourceAsset.displayName,
                    sortOrder: asCover ? 0 : sourceAsset.sortOrder
                ),
                analysisImage: image,
                didExtract: false
            )
        }

        if !sourceAsset.localIdentifier.isEmpty {
            LocalMediaFileStore.shared.deleteFile(for: sourceAsset.localIdentifier)
        }

        let analysisImage = extracted.originalData.flatMap(UIImage.init(data:)) ?? image
        if asCover {
            return (
                asset: extracted.with(
                    itemID: itemID,
                    displayName: String(localized: "editor.media.cover"),
                    sortOrder: 0
                ),
                analysisImage: analysisImage,
                didExtract: true
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

        return (asset: asset, analysisImage: analysisImage, didExtract: true)
    }
}
