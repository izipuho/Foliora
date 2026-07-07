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

    private let style: BellCardStyle
    private let cardMetrics: CatalogCardLayoutMode.CardMetrics

    init(
        bell: some BellCardDisplayable,
        layoutMode: CatalogCardLayoutMode,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) {
        self.bell = bell
        self.cardSize = cardSize
        self.style = BellCardStyle.style(for: layoutMode)
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

            if style.title != nil && style.meta != nil {
                Spacer()
            }

            if let metaStyle = style.meta {
                BellCardMetaBlock(
                    bell: bell,
                    style: metaStyle,
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
}

private struct BellCardStyle {
    enum MetaField: Hashable {
        case year
    }

    struct TitleBlockStyle {
        let titleFont: Font
        let titleLineLimit: Int
        let showsSubtitle: Bool
        let subtitleFont: Font
        let subtitleLineLimit: Int
        let spacing: CGFloat
    }

    struct MetaBlockStyle {
        let fields: [MetaField]
        let chipSpacing: CGFloat
    }

    let title: TitleBlockStyle?
    let meta: MetaBlockStyle?

    static let covers = BellCardStyle(
        title: TitleBlockStyle(
            titleFont: .caption.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: false,
            subtitleFont: .caption2,
            subtitleLineLimit: 1,
            spacing: CatalogMetrics.Spacing.xxs
        ),
        meta: nil
    )

    static let mini = BellCardStyle(
        title: TitleBlockStyle(
            titleFont: .subheadline.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: false,
            subtitleFont: .caption2,
            subtitleLineLimit: 1,
            spacing: CatalogMetrics.Spacing.xs
        ),
        meta: MetaBlockStyle(
            fields: [.year],
            chipSpacing: 8
        )
    )

    static let compact = BellCardStyle(
        title: TitleBlockStyle(
            titleFont: .headline.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: true,
            subtitleFont: .caption,
            subtitleLineLimit: 2,
            spacing: CatalogMetrics.Spacing.xs
        ),
        meta: MetaBlockStyle(
            fields: [.year],
            chipSpacing: 8
        )
    )

    static let wide = BellCardStyle(
        title: TitleBlockStyle(
            titleFont: .headline.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: true,
            subtitleFont: .caption,
            subtitleLineLimit: 2,
            spacing: CatalogMetrics.Spacing.xs
        ),
        meta: MetaBlockStyle(
            fields: [.year],
            chipSpacing: 8
        )
    )

    static let showcase = BellCardStyle(
        title: TitleBlockStyle(
            titleFont: .title.weight(.semibold),
            titleLineLimit: 3,
            showsSubtitle: true,
            subtitleFont: .body,
            subtitleLineLimit: 2,
            spacing: CatalogMetrics.Spacing.xs
        ),
        meta: MetaBlockStyle(
            fields: [.year],
            chipSpacing: 8
        )
    )

    private static let registry: [CatalogCardLayoutMode: BellCardStyle] = [
        .covers: .covers,
        .mini: .mini,
        .compact: .compact,
        .wide: .wide,
        .showcase: .showcase
    ]

    static func style(for layoutMode: CatalogCardLayoutMode) -> BellCardStyle {
        registry[layoutMode] ?? .compact
    }
}

private struct BellCardTitleBlock: View {
    let bell: any BellCardDisplayable
    let style: BellCardStyle.TitleBlockStyle
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

private struct BellCardMetaBlock: View {
    let bell: any BellCardDisplayable
    let style: BellCardStyle.MetaBlockStyle
    let bright: Bool

    private var metaItems: [BellCardMetaItem] {
        style.fields.compactMap { field in
            switch field {
            case .year:
                guard let acquiredYear = bell.acquiredYear else {
                    return nil
                }

                return BellCardMetaItem(
                    label: String(acquiredYear)
                )
            }
        }
    }

    var body: some View {
        HStack(spacing: style.chipSpacing) {
            ForEach(metaItems) { item in
                BellCardMetaChip(
                    label: item.label,
                    bright: bright
                )
            }
        }
    }
}

private struct BellCardMetaItem: Identifiable {
    let label: String

    var id: String {
        label
    }
}

private struct BellCardMetaChip: View {
    let label: String
    let bright: Bool

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, CatalogMetrics.Spacing.sm)
            .padding(.vertical, CatalogMetrics.Spacing.xs)
            .background(
                bright
                    ? CatalogMediaContrast.glassFill
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .foregroundStyle(bright ? CatalogMediaContrast.onMediaPrimary : .secondary)
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
