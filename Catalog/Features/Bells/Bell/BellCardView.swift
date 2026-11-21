import SwiftUI

/// Displays the bell card view interface.
struct BellCardView: View {
    let bell: BellCatalogItem
    let cardSize: CGSize

    private let style: CatalogCardContentStyle
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics

    init(
        bell: BellCatalogItem,
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
                if let coverPhotoID = bell.coverPhotoID, hasCoverPhoto {
                    MediaPreviewImage(assetID: coverPhotoID, size: cardSize)
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
        bell.coverPhotoID != nil
    }

    private var accessories: [CatalogCardAccessory] {
        var accessories: [CatalogCardAccessory] = []

        if let acquiredYear = bell.acquiredYear {
            accessories.append(.chip(String(acquiredYear)))
        }

        if let color = bell.color {
            accessories.append(
                .text(
                    color.displayName,
                    accessibilityLabel: String.localizedStringWithFormat(
                        String(localized: "common.field.color_format"),
                        color.displayName
                    )
                )
            )
        }

        if bell.size != .unknown {
            accessories.append(
                .text(
                    bell.size.displayName,
                    accessibilityLabel: String.localizedStringWithFormat(
                        String(localized: "common.field.size_format"),
                        bell.size.displayName
                    )
                )
            )
        }

        return accessories
    }
}
