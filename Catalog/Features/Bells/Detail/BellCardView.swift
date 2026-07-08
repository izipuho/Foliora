import SwiftUI

protocol BellCardDisplayable {
    var id: UUID { get }
    var title: String { get }
    var placeDisplayName: String { get }
    var acquiredYear: Int? { get }
    var coverPhotoIdentifier: String? { get }
    var coverPhotoThumbnailData: Data? { get }
    var coverPhotoOriginalData: Data? { get }
}

extension BellRecord: BellCardDisplayable {
    private var coverPhoto: MediaAsset? {
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    var coverPhotoIdentifier: String? {
        coverPhoto?.localIdentifier
    }

    var coverPhotoThumbnailData: Data? {
        coverPhoto?.thumbnailData
    }

    var coverPhotoOriginalData: Data? {
        coverPhoto?.originalData
    }
}

struct BellCardView: View {
    let bell: any BellCardDisplayable
    let cardSize: CGSize

    private let layoutMode: CatalogCardLayoutMode
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics

    init(
        bell: some BellCardDisplayable,
        layoutMode: CatalogCardLayoutMode,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) {
        self.bell = bell
        self.cardSize = cardSize
        self.layoutMode = layoutMode
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

    private var style: CatalogCardContentStyle {
        CatalogCardContentStyle.style(for: layoutMode)
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
