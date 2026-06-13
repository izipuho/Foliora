import SwiftUI
import UIKit

enum CatalogCornerRadii {
    static let hero: CGFloat = 28
    static let section: CGFloat = 24
    static let medium: CGFloat = 18
    static let tile: CGFloat = 16
    static let highlight: CGFloat = 14
    static let thumbnail: CGFloat = 12
}

enum CatalogLayoutInsets {
    static let screen: CGFloat = 8 
    static let overlay: CGFloat = 8 
}

enum CatalogSpacing {
    static let micro: CGFloat = 4
    static let compact: CGFloat = 6
    static let regular: CGFloat = 12
    static let section: CGFloat = 24
}

enum CatalogSemanticColors {
    static let separator = Color(uiColor: .separator)
    static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedSurfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let fill = Color(uiColor: .systemFill)
    static let secondaryFill = Color(uiColor: .secondarySystemFill)
    static let tertiaryFill = Color(uiColor: .tertiarySystemFill)
    static let quaternaryFill = Color(uiColor: .quaternarySystemFill)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
}

enum CatalogMediaContrast {
    static let coverScrimBottom = Color.black.opacity(0.22)
    static let coverScrimTop = Color.black.opacity(0.02)
    static let overlayChip = Color.white.opacity(0.16)
    static let overlayChipMuted = Color.white.opacity(0.72)
    static let glassStroke = Color.white.opacity(0.32)
    static let mediaSelectionStroke = Color.white.opacity(0.9)
    static let previewGradientStart = Color.white.opacity(0.88)
    static let previewGradientEnd = Color.white.opacity(0.72)
    static let mapScrimTop = Color.black.opacity(0)
    static let mapScrimMiddle = Color.black.opacity(0.10)
    static let mapScrimBottom = Color.black.opacity(0.30)
    static let iconPaletteShadowSoft = Color.black.opacity(0.25)
    static let iconPaletteShadowStrong = Color.black.opacity(0.35)
}

struct CatalogShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

enum CatalogElevation {
    static let card = CatalogShadowStyle(
        color: CatalogSemanticColors.separator.opacity(0.22),
        radius: 12,
        y: 6
    )

    static let floatingCard = CatalogShadowStyle(
        color: CatalogSemanticColors.separator.opacity(0.22),
        radius: 14,
        y: 8
    )

    static let collectionCard = CatalogShadowStyle(
        color: CatalogSemanticColors.separator.opacity(0.22),
        radius: 16,
        y: 8
    )

    static let detailSection = CatalogShadowStyle(
        color: CatalogSemanticColors.separator.opacity(0.22),
        radius: 10,
        y: 4
    )

    static func highlightedDetailSection(tint: Color) -> CatalogShadowStyle {
        CatalogShadowStyle(
            color: tint.opacity(0.14),
            radius: 14,
            y: 4
        )
    }
}

enum CatalogPillPadding {
    case micro
    case compact
    case regular
    case prominent

    var horizontal: CGFloat {
        switch self {
        case .micro: return 6
        case .compact: return 8
        case .regular: return 12
        case .prominent: return 14
        }
    }

    var vertical: CGFloat {
        switch self {
        case .micro: return 3
        case .compact: return 6
        case .regular: return 8
        case .prominent: return 10
        }
    }
}

extension View {
    func catalogPillPadding(_ style: CatalogPillPadding) -> some View {
        padding(.horizontal, style.horizontal)
            .padding(.vertical, style.vertical)
    }

    func catalogShadow(_ style: CatalogShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }
}

enum BellGridLayoutMode: Int, CaseIterable {
    case covers
    case mini
    case compact
    case wide
    case showcase

    struct GridMetrics {
        let columnCount: Int
        let spacing: CGFloat
    }

    struct CardMetrics {
        let cardHeight: CGFloat
        let cardPadding: CGFloat
        let contentSpacing: CGFloat
        let contentAlignment: Alignment
        let cornerRadius: CGFloat
        let imagePreviewHeight: CGFloat
    }

    static let screenHorizontalPadding: CGFloat = CatalogLayoutInsets.screen

    var gridMetrics: GridMetrics {
        switch self {
        case .covers:
            return GridMetrics(
                columnCount: 4,
                spacing: CatalogSpacing.micro
            )
        case .mini:
            return GridMetrics(
                columnCount: 3,
                spacing: CatalogSpacing.micro
            )
        case .compact:
            return GridMetrics(
                columnCount: 2,
                spacing: CatalogSpacing.compact
            )
        case .wide:
            return GridMetrics(
                columnCount: 1,
                spacing: CatalogSpacing.compact
            )
        case .showcase:
            return GridMetrics(
                columnCount: 1,
                spacing: CatalogSpacing.regular
            )
        }
    }

    func gridMetrics(forContainerWidth containerWidth: CGFloat) -> GridMetrics {
        let base = gridMetrics
        let usableWidth = max(containerWidth - (BellGridLayoutMode.screenHorizontalPadding * GridSizingRules.horizontalPaddingMultiplier), 0)
        let availableColumnCount = Int(floor((usableWidth + base.spacing) / (referenceCardWidth + base.spacing)))
        let columnCount = min(max(availableColumnCount, base.columnCount), maxColumnCount)

        return GridMetrics(
            columnCount: columnCount,
            spacing: base.spacing
        )
    }

    var cardMetrics: CardMetrics {
        switch self {
        case .covers:
            return CardMetrics(
                cardHeight: 108,
                cardPadding: 8,
                contentSpacing: 4,
                //contentAlignment: .bottomLeading,
                contentAlignment: .topLeading,
                cornerRadius: CatalogCornerRadii.tile,
                imagePreviewHeight: 210
            )
        case .mini:
            return CardMetrics(
                cardHeight: 144,
                cardPadding: 10,
                contentSpacing: 4,
                contentAlignment: .topLeading,
                cornerRadius: CatalogCornerRadii.tile,
                imagePreviewHeight: 210
            )
        case .compact:
            return CardMetrics(
                cardHeight: 220,
                cardPadding: 14,
                contentSpacing: 8,
                contentAlignment: .topLeading,
                cornerRadius: CatalogCornerRadii.tile,
                imagePreviewHeight: 210
            )
        case .wide:
            return CardMetrics(
                cardHeight: 220,
                cardPadding: 18,
                contentSpacing: 8,
                contentAlignment: .topLeading,
                cornerRadius: CatalogCornerRadii.tile,
                imagePreviewHeight: 210
            )
        case .showcase:
            return CardMetrics(
                cardHeight: 460,
                cardPadding: 22,
                contentSpacing: 12,
                contentAlignment: .topLeading,
                cornerRadius: CatalogCornerRadii.hero,
                imagePreviewHeight: 210
            )
        }
    }

    func cardMetrics(forCardWidth cardWidth: CGFloat) -> CardMetrics {
        let base = cardMetrics
        let widthGrowth = max((cardWidth / referenceCardWidth) - CardMetricScaleLimits.baselineScale, 0)
        let heightScale = min(
            CardMetricScaleLimits.baselineScale + (widthGrowth * CardMetricScaleLimits.heightGrowthMultiplier),
            CardMetricScaleLimits.maxHeightScale
        )
        let imagePreviewScale = min(
            CardMetricScaleLimits.baselineScale + (widthGrowth * CardMetricScaleLimits.imagePreviewGrowthMultiplier),
            CardMetricScaleLimits.maxImagePreviewScale
        )
        let paddingScale = min(
            CardMetricScaleLimits.baselineScale + (widthGrowth * CardMetricScaleLimits.paddingGrowthMultiplier),
            CardMetricScaleLimits.maxPaddingScale
        )
        let contentSpacingScale = min(
            CardMetricScaleLimits.baselineScale + (widthGrowth * CardMetricScaleLimits.contentSpacingGrowthMultiplier),
            CardMetricScaleLimits.maxContentSpacingScale
        )
        let cornerRadiusScale = min(
            CardMetricScaleLimits.baselineScale + (widthGrowth * CardMetricScaleLimits.cornerRadiusGrowthMultiplier),
            CardMetricScaleLimits.maxCornerRadiusScale
        )

        return CardMetrics(
            cardHeight: base.cardHeight * heightScale,
            cardPadding: base.cardPadding * paddingScale,
            contentSpacing: base.contentSpacing * contentSpacingScale,
            contentAlignment: base.contentAlignment,
            cornerRadius: base.cornerRadius * cornerRadiusScale,
            imagePreviewHeight: base.imagePreviewHeight * imagePreviewScale
        )
    }

    private var referenceCardWidth: CGFloat {
        switch self {
        case .covers: return GridSizingRules.preferredMinimumCoversCardWidth
        case .mini: return GridSizingRules.preferredMinimumMiniCardWidth
        case .compact: return GridSizingRules.preferredMinimumCompactCardWidth
        case .wide: return GridSizingRules.preferredMinimumWideCardWidth
        case .showcase: return GridSizingRules.preferredMinimumShowcaseCardWidth
        }
    }

    private var maxColumnCount: Int {
        switch self {
        case .covers: return GridColumnLimits.maxCoversColumns
        case .mini: return GridColumnLimits.maxMiniColumns
        case .compact: return GridColumnLimits.maxCompactColumns
        case .wide: return GridColumnLimits.maxWideColumns
        case .showcase: return GridColumnLimits.maxShowcaseColumns
        }
    }

    func cardWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        let currentMetrics = gridMetrics(forContainerWidth: containerWidth)
        return cardWidth(forContainerWidth: containerWidth, gridMetrics: currentMetrics)
    }

    func cardWidth(forContainerWidth containerWidth: CGFloat, gridMetrics currentMetrics: GridMetrics) -> CGFloat {
        let totalSpacing = currentMetrics.spacing * CGFloat(max(currentMetrics.columnCount - 1, 0))
        let usableWidth = max(containerWidth - (BellGridLayoutMode.screenHorizontalPadding * GridSizingRules.horizontalPaddingMultiplier) - totalSpacing, 0)
        return floor(usableWidth / CGFloat(currentMetrics.columnCount))
    }
}

private enum CardMetricScaleLimits {
    static let baselineScale: CGFloat = 1
    static let heightGrowthMultiplier: CGFloat = 0.35
    static let imagePreviewGrowthMultiplier: CGFloat = 0.65
    static let paddingGrowthMultiplier: CGFloat = 0.16
    static let contentSpacingGrowthMultiplier: CGFloat = 0.14
    static let cornerRadiusGrowthMultiplier: CGFloat = 0.12
    static let maxHeightScale: CGFloat = 1.18
    static let maxImagePreviewScale: CGFloat = 1.32
    static let maxPaddingScale: CGFloat = 1.10
    static let maxContentSpacingScale: CGFloat = 1.10
    static let maxCornerRadiusScale: CGFloat = 1.08
}

private enum GridColumnLimits {
    static let maxCoversColumns = 8
    static let maxMiniColumns = 6
    static let maxCompactColumns = 4
    static let maxWideColumns = 3
    static let maxShowcaseColumns = 2
}

private enum GridSizingRules {
    static let horizontalPaddingMultiplier: CGFloat = 2
    static let preferredMinimumCoversCardWidth: CGFloat = 90
    static let preferredMinimumMiniCardWidth: CGFloat = 123
    static let preferredMinimumCompactCardWidth: CGFloat = 185
    static let preferredMinimumWideCardWidth: CGFloat = 377
    static let preferredMinimumShowcaseCardWidth: CGFloat = 377
}

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
    private let cardMetrics: BellGridLayoutMode.CardMetrics

    init(
        bell: some BellCardDisplayable,
        layoutMode: BellGridLayoutMode,
        cardSize: CGSize,
        cardMetrics: BellGridLayoutMode.CardMetrics
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
                hasCoverPhoto ? CatalogMediaContrast.coverScrimBottom : .clear,
                hasCoverPhoto ? CatalogMediaContrast.coverScrimTop : .clear
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
        hasCoverPhoto ? .white : .primary
    }

    private var secondaryTextColor: Color {
        hasCoverPhoto ? .white.opacity(0.86) : .secondary
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
            spacing: 2
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
            spacing: 4
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
            spacing: 4
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
            spacing: 4
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
            spacing: 6
        ),
        meta: MetaBlockStyle(
            fields: [.year],
            chipSpacing: 8
        )
    )

    private static let registry: [BellGridLayoutMode: BellCardStyle] = [
        .covers: .covers,
        .mini: .mini,
        .compact: .compact,
        .wide: .wide,
        .showcase: .showcase
    ]

    static func style(for layoutMode: BellGridLayoutMode) -> BellCardStyle {
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
            .catalogPillPadding(.compact)
            .background(
                bright
                    ? CatalogMediaContrast.overlayChip
                    : CatalogSemanticColors.groupedSurface,
                in: Capsule()
            )
            .foregroundStyle(bright ? .white : .secondary)
    }
}

struct BellCardStripView<Bell: BellCardDisplayable>: View {
    let bells: [Bell]
    let layoutMode: BellGridLayoutMode
    let screenWidth: CGFloat
    let onSelect: (Bell) -> Void

    var body: some View {
        let gridMetrics = layoutMode.gridMetrics(forContainerWidth: screenWidth)
        let width = layoutMode.cardWidth(forContainerWidth: screenWidth, gridMetrics: gridMetrics)
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
            .padding(.horizontal, CatalogSpacing.compact)
        }
        .frame(height: cardMetrics.cardHeight)
    }
}

struct BellCardImagePreviewView: View {
    let bell: any BellCardDisplayable
    private let cardMetrics = BellGridLayoutMode.wide.cardMetrics

    var body: some View {
        GeometryReader { proxy in
            BellCardView(
                bell: bell,
                layoutMode: .wide,
                cardSize: CGSize(width: proxy.size.width, height: cardMetrics.imagePreviewHeight),
                cardMetrics: cardMetrics
            )
        }
        .frame(height: cardMetrics.imagePreviewHeight)
        .padding(.horizontal, CatalogLayoutInsets.screen)
        .padding(.top, CatalogSpacing.regular)
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
                        CatalogMediaContrast.previewGradientStart,
                        CatalogMediaContrast.previewGradientEnd
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
