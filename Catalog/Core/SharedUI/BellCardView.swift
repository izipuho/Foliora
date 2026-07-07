import SwiftUI
import UIKit

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

    private let style: CatalogCardContentStyle
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics

    init(
        bell: some BellCardDisplayable,
        layoutMode: CatalogCardLayoutMode,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) {
        self.bell = bell
        self.cardSize = cardSize
        self.style = CatalogCardContentStyle.style(for: layoutMode)
        self.cardMetrics = cardMetrics
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if hasCoverPhoto {
                BellCardCoverBackground(
                    identifier: bell.coverPhotoIdentifier,
                    thumbnailData: bell.coverPhotoThumbnailData,
                    originalData: bell.coverPhotoOriginalData,
                    size: cardSize
                )
            }

            coverScrim
                .frame(width: cardSize.width, height: cardSize.height)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .overlay(alignment: .topLeading) {
            cardContent(in: cardSize)
        }
        .clipShape(cardShape)
        .contentShape(cardShape)
    }

    @ViewBuilder
    private func cardContent(in size: CGSize) -> some View {
        let contentWidth = max(size.width - (cardMetrics.cardPadding * 2), 0)
        let contentHeight = max(size.height - (cardMetrics.cardPadding * 2), 0)

        VStack(alignment: .leading, spacing: cardMetrics.contentSpacing) {
            if let titleStyle = style.title {
                BellCardTitleBlock(
                    bell: bell,
                    style: titleStyle,
                    primaryTextColor: primaryTextColor,
                    secondaryTextColor: secondaryTextColor
                )
            }

            if style.title != nil && style.accessoryRow != nil {
                Spacer()
            }

            if let accessoryRowStyle = style.accessoryRow {
                CatalogCardAccessoryRow(
                    accessories: accessories,
                    style: accessoryRowStyle,
                    bright: hasCoverPhoto
                )
            }
        }
        .frame(width: contentWidth, height: contentHeight, alignment: cardMetrics.contentAlignment)
        .padding(cardMetrics.cardPadding)
    }

    private var coverScrim: some View {
        LinearGradient(
            colors: [
                hasCoverPhoto ? CatalogMediaContrast.scrimMedium : .clear,
                hasCoverPhoto ? CatalogMediaContrast.scrimClear : .clear
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardMetrics.cornerRadius, style: .continuous)
    }

    private var hasCoverPhoto: Bool {
        bell.coverPhotoThumbnailData != nil || bell.coverPhotoIdentifier != nil || bell.coverPhotoOriginalData != nil
    }

    private var primaryTextColor: Color {
        hasCoverPhoto ? CatalogMediaContrast.onMediaPrimary : .primary
    }

    private var secondaryTextColor: Color {
        hasCoverPhoto ? CatalogMediaContrast.glassFill : .secondary
    }

    private var accessories: [CatalogCardAccessory] {
        guard let acquiredYear = bell.acquiredYear else {
            return []
        }

        return [.chip(String(acquiredYear))]
    }
}

private struct BellCardTitleBlock: View {
    let bell: any BellCardDisplayable
    let style: CatalogCardContentStyle.TitleBlockStyle
    let primaryTextColor: Color
    let secondaryTextColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            Text(bell.title)
                .font(style.titleFont)
                .foregroundStyle(primaryTextColor)
                .lineLimit(style.titleLineLimit)

            if style.showsSubtitle {
                Text(bell.placeDisplayName)
                    .font(style.subtitleFont)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(style.subtitleLineLimit)
            }
        }
    }
}

struct BellCardStripView<Bell: BellCardDisplayable>: View {
    let bells: [Bell]
    let layoutMode: CatalogCardLayoutMode
    let screenWidth: CGFloat
    let onSelect: (Bell) -> Void

    var body: some View {
        let gridMetrics = layoutMode.gridMetrics(forContainerWidth: screenWidth)
        let width = layoutMode.cardWidth(forContainerWidth: screenWidth)
        let cardMetrics = layoutMode.cardMetrics(forCardWidth: width)
        let cardSize = CGSize(width: width, height: cardMetrics.cardHeight)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gridMetrics.spacing) {
                ForEach(bells, id: \.id) { bell in
                    Button {
                        onSelect(bell)
                    } label: {
                        BellCardView(
                            bell: bell,
                            layoutMode: layoutMode,
                            cardSize: cardSize,
                            cardMetrics: cardMetrics
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CatalogMetrics.Spacing.xs)
        }
        .frame(height: cardMetrics.cardHeight)
    }
}

struct BellCardCoverBackground: View {
    let identifier: String?
    let thumbnailData: Data?
    let originalData: Data?
    let size: CGSize
    private let mediaStore = LocalMediaFileStore.shared
    private let thumbnailCache = ThumbnailImageCache.shared
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        CatalogMediaContrast.onMediaPrimary.opacity(0.88),
                        CatalogMediaContrast.onMediaPrimary.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)
            }
        }
        .task(id: thumbnailTaskID) {
            await loadImage()
        }
    }

    private var thumbnailTaskID: String {
        let pixelWidth = Int((size.width * displayScale).rounded(.up))
        let pixelHeight = Int((size.height * displayScale).rounded(.up))
        return "\(identifier ?? "data")-\(thumbnailData?.count ?? 0)-\(originalData?.count ?? 0)-\(pixelWidth)x\(pixelHeight)"
    }

    @MainActor
    private func loadImage() async {
        if let thumbnailData {
            if let loadedImage = UIImage(data: thumbnailData) {
                image = loadedImage
                return
            }
        }

        if let identifier,
           let url = mediaStore.thumbnailFileURL(for: identifier) ?? mediaStore.fileURL(for: identifier) {
            if let loadedImage = await thumbnailCache.image(
                identifier: identifier,
                url: url,
                targetSize: size,
                scale: displayScale
            ) {
                image = loadedImage
                return
            }
        }

        if let originalData {
            if let loadedImage = UIImage(data: originalData) {
                image = loadedImage
            }
        }
    }
}
