import UIKit

struct BookCreationMedia {
    let coverImage: MediaAsset?
    let mediaAssets: [MediaAsset]
    let usedOriginalCover: Bool

    var recognitionAssets: [MediaAsset] {
        [coverImage].compactMap { $0 } + mediaAssets
    }
}

extension ItemCreationService {
    @MainActor
    static func prepareBookMedia(
        _ assets: [MediaAsset],
        itemID: UUID
    ) async -> BookCreationMedia {
        let orderedPhotos = assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let source = orderedPhotos.first else {
            return BookCreationMedia(
                coverImage: nil,
                mediaAssets: normalizedBookMedia(assets, itemID: itemID),
                usedOriginalCover: false
            )
        }

        let originalCover = source.with(
            itemID: itemID,
            displayName: String(localized: "editor.media.cover"),
            sortOrder: 0
        )

        let coverImage: MediaAsset
        let usedOriginalCover: Bool

        if let sourceImage = image(for: source),
           let extracted = await BookCoverExtractor().extractCover(from: sourceImage) {
            coverImage = extracted.with(
                itemID: itemID,
                displayName: String(localized: "editor.media.cover"),
                sortOrder: 0
            )
            usedOriginalCover = false

            if !source.localIdentifier.isEmpty {
                LocalMediaFileStore.shared.deleteFile(for: source.localIdentifier)
            }
        } else {
            coverImage = originalCover
            usedOriginalCover = true
        }

        let remainingMedia = assets.filter { $0.id != source.id }

        return BookCreationMedia(
            coverImage: coverImage,
            mediaAssets: normalizedBookMedia(remainingMedia, itemID: itemID),
            usedOriginalCover: usedOriginalCover
        )
    }

    private static func normalizedBookMedia(
        _ assets: [MediaAsset],
        itemID: UUID
    ) -> [MediaAsset] {
        assets
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, asset in
                asset.with(itemID: itemID, sortOrder: index)
            }
    }
}
