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
    static let screen: CGFloat = 20
    static let overlay: CGFloat = 16
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

    struct Metrics {
        let columnCount: Int
        let cardHeight: CGFloat
        let cardPadding: CGFloat
        let spacing: CGFloat
    }

    static let screenHorizontalPadding: CGFloat = CatalogLayoutInsets.screen

    var metrics: Metrics {
        switch self {
        case .covers:
            return Metrics(columnCount: 4, cardHeight: 92, cardPadding: 0, spacing: 8)
        case .mini:
            return Metrics(columnCount: 3, cardHeight: 144, cardPadding: 10, spacing: 10)
        case .compact:
            return Metrics(columnCount: 2, cardHeight: 220, cardPadding: 14, spacing: 12)
        case .wide:
            return Metrics(columnCount: 1, cardHeight: 220, cardPadding: 18, spacing: 14)
        case .showcase:
            return Metrics(columnCount: 1, cardHeight: 460, cardPadding: 22, spacing: 18)
        }
    }

    var columnCount: Int { metrics.columnCount }
    var cardHeight: CGFloat { metrics.cardHeight }
    var cardPadding: CGFloat { metrics.cardPadding }
    var spacing: CGFloat { metrics.spacing }

    func cardWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(max(columnCount - 1, 0))
        let usableWidth = max(containerWidth - (BellGridLayoutMode.screenHorizontalPadding * 2) - totalSpacing, 0)
        return floor(usableWidth / CGFloat(columnCount))
    }

    var stripHeight: CGFloat {
        cardHeight + spacing
    }
}

protocol BellCardDisplayable {
    var id: UUID { get }
    var title: String { get }
    var placeDisplayName: String { get }
    var acquiredYear: Int? { get }
    var coverPhotoIdentifier: String? { get }
}

extension BellEntity: BellCardDisplayable {
    var coverPhotoIdentifier: String? {
        coverPhotoAsset?.localIdentifier
    }
}

extension BellRecord: BellCardDisplayable {
    var coverPhotoIdentifier: String? {
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .localIdentifier
    }
}

struct BellCardView: View {
    let bell: any BellCardDisplayable
    let layoutMode: BellGridLayoutMode
    let cardSize: CGSize

    private let style: BellCardStyle
    private let cornerRadius: CGFloat

    init(bell: some BellCardDisplayable, layoutMode: BellGridLayoutMode, cardSize: CGSize) {
        self.bell = bell
        self.layoutMode = layoutMode
        self.cardSize = cardSize
        self.style = BellCardStyle.style(for: layoutMode)
        self.cornerRadius = BellCardStyle.cornerRadius(for: layoutMode)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let coverPhotoIdentifier = bell.coverPhotoIdentifier {
                BellCardCoverBackground(
                    identifier: coverPhotoIdentifier,
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
        let contentWidth = max(size.width - (layoutMode.cardPadding * 2), 0)
        let contentHeight = max(size.height - (layoutMode.cardPadding * 2), 0)

        VStack(alignment: .leading, spacing: style.contentSpacing) {
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
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        .padding(layoutMode.cardPadding)
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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var hasCoverPhoto: Bool {
        bell.coverPhotoIdentifier != nil
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
    let contentSpacing: CGFloat

    static let covers = BellCardStyle(
        title: nil,
        meta: nil,
        contentSpacing: 4
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
        ),
        contentSpacing: 4
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
        ),
        contentSpacing: 8
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
        ),
        contentSpacing: 8
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
        ),
        contentSpacing: 12
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

    static func cornerRadius(for layoutMode: BellGridLayoutMode) -> CGFloat {
        layoutMode == .showcase ? CatalogCornerRadii.hero : CatalogCornerRadii.tile
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
        let width = layoutMode.cardWidth(forContainerWidth: screenWidth)
        let cardSize = CGSize(width: width, height: layoutMode.cardHeight)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: layoutMode.spacing) {
                ForEach(bells, id: \.id) { bell in
                    Button {
                        onSelect(bell)
                    } label: {
                        BellCardView(
                            bell: bell,
                            layoutMode: layoutMode,
                            cardSize: cardSize
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: layoutMode.cardHeight)
    }
}

struct BellCardHeroView: View {
    let bell: any BellCardDisplayable

    var body: some View {
        GeometryReader { proxy in
            BellCardView(
                bell: bell,
                layoutMode: .wide,
                cardSize: CGSize(width: proxy.size.width, height: 210)
            )
        }
        .frame(height: 210)
        .padding(.horizontal, CatalogLayoutInsets.screen)
        .padding(.top, CatalogSpacing.regular)
    }
}

struct BellCardCoverBackground: View {
    let identifier: String
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
        .onChange(of: identifier) { _, _ in
            image = nil
        }
    }

    private var thumbnailTaskID: String {
        let pixelWidth = Int((size.width * displayScale).rounded(.up))
        let pixelHeight = Int((size.height * displayScale).rounded(.up))
        return "\(identifier)-\(pixelWidth)x\(pixelHeight)"
    }

    @MainActor
    private func loadImage() async {
        guard let url = mediaStore.fileURL(for: identifier),
              let loadedImage = await thumbnailCache.image(
                identifier: identifier,
                url: url,
                targetSize: size,
                scale: displayScale
              ) else {
            return
        }

        image = loadedImage
    }
}
