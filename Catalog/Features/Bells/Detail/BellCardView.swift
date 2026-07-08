import SwiftUI

extension BellRecord {
    private var coverPhoto: MediaAsset? {
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    var coverPhotoIdentifier: String? {
        guard let localIdentifier = coverPhoto?.localIdentifier, !localIdentifier.isEmpty else {
            return nil
        }

        return localIdentifier
    }

    var coverPhotoThumbnailData: Data? {
        coverPhoto?.thumbnailData
    }

    var coverPhotoOriginalData: Data? {
        coverPhoto?.originalData
    }
}

struct BellCardView: View {
    let bell: BellRecord
    let cardSize: CGSize

    private let style: CatalogCardContentStyle
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics

    init(
        bell: BellRecord,
        style: CatalogCardContentStyle,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) {
        self.bell = bell
        self.cardSize = cardSize
        self.style = style
        self.cardMetrics = cardMetrics
    }

    var body: some View {
        catalogCardContent
            .catalogSurfaceCard(cardMetrics: cardMetrics) {
                if hasCoverPhoto {
                    MediaPreviewImage(
                        identifier: bell.coverPhotoIdentifier,
                        thumbnailData: bell.coverPhotoThumbnailData,
                        originalData: bell.coverPhotoOriginalData,
                        size: cardSize
                    )
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
    }

    private var catalogCardContent: some View {
        CatalogCardContent(
            title: bell.title,
            subtitle: bell.placeDisplayName,
            accessories: accessories,
            style: style,
            bright: hasCoverPhoto,
            cardSize: cardSize,
            cardMetrics: cardMetrics
        )
    }

    private var hasCoverPhoto: Bool {
        bell.coverPhotoThumbnailData != nil || bell.coverPhotoIdentifier != nil || bell.coverPhotoOriginalData != nil
    }

    private var accessories: [CatalogCardAccessory] {
        guard let acquiredYear = bell.acquiredYear else {
            return []
        }

        return [.chip(String(acquiredYear))]
    }
}
