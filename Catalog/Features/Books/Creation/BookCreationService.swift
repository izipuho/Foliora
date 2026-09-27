import UIKit

/// Represents the prepared media state for one new book.
///
/// Cover determination happens exactly once while this draft is prepared.
/// The selected source photo is never left both as a cover and as regular media.
struct BookCreationDraft {
    let itemID: UUID
    let coverImage: MediaAsset?
    let mediaAssets: [MediaAsset]
    let usedOriginalCover: Bool

    var recognitionAssets: [MediaAsset] {
        [coverImage].compactMap { $0 } + mediaAssets
    }
}

extension ItemCreationService {
    /// Prepares the canonical creation draft used by both single and batch book creation.
    ///
    /// The first photo becomes the dedicated cover. If cover extraction fails, the
    /// original photo itself becomes that dedicated cover. Remaining assets stay as
    /// regular book media.
    @MainActor
    static func prepareBookDraft(
        _ assets: [MediaAsset],
        itemID: UUID = UUID()
    ) async -> BookCreationDraft {
        let orderedPhotos = assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let source = orderedPhotos.first else {
            return BookCreationDraft(
                itemID: itemID,
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

        return BookCreationDraft(
            itemID: itemID,
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
