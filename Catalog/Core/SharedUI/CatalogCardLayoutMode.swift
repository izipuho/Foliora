import SwiftUI

enum CatalogCardLayoutMode: Int, CaseIterable {
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
    }

    static let screenHorizontalPadding: CGFloat = CatalogMetrics.Insets.screen

    var gridMetrics: GridMetrics {
        switch self {
        case .covers:
            return GridMetrics(
                columnCount: 4,
                spacing: CatalogMetrics.Spacing.xs
            )
        case .mini:
            return GridMetrics(
                columnCount: 3,
                spacing: CatalogMetrics.Spacing.xs
            )
        case .compact:
            return GridMetrics(
                columnCount: 2,
                spacing: CatalogMetrics.Spacing.xs
            )
        case .wide:
            return GridMetrics(
                columnCount: 1,
                spacing: CatalogMetrics.Spacing.xs
            )
        case .showcase:
            return GridMetrics(
                columnCount: 1,
                spacing: CatalogMetrics.Spacing.md
            )
        }
    }

    var cardMetrics: CardMetrics {
        switch self {
        case .covers:
            return CardMetrics(
                cardHeight: 108,
                cardPadding: CatalogMetrics.Spacing.sm,
                contentSpacing: CatalogMetrics.Spacing.xs,
                contentAlignment: .topLeading,
                cornerRadius: CatalogMetrics.CornerRadius.thumbnail
            )
        case .mini:
            return CardMetrics(
                cardHeight: 144,
                cardPadding: CatalogMetrics.Spacing.md,
                contentSpacing: CatalogMetrics.Spacing.xs,
                contentAlignment: .topLeading,
                cornerRadius: CatalogMetrics.CornerRadius.tile
            )
        case .compact:
            return CardMetrics(
                cardHeight: 220,
                cardPadding: CatalogMetrics.Spacing.lg,
                contentSpacing: CatalogMetrics.Spacing.sm,
                contentAlignment: .topLeading,
                cornerRadius: CatalogMetrics.CornerRadius.medium
            )
        case .wide:
            return CardMetrics(
                cardHeight: 220,
                cardPadding: CatalogMetrics.Spacing.lg,
                contentSpacing: CatalogMetrics.Spacing.sm,
                contentAlignment: .topLeading,
                cornerRadius: CatalogMetrics.CornerRadius.hero
            )
        case .showcase:
            return CardMetrics(
                cardHeight: 460,
                cardPadding: CatalogMetrics.Spacing.xl,
                contentSpacing: CatalogMetrics.Spacing.md,
                contentAlignment: .topLeading,
                cornerRadius: CatalogMetrics.CornerRadius.hero
            )
        }
    }

    func gridMetrics(forContainerWidth containerWidth: CGFloat) -> GridMetrics {
        let base = gridMetrics
        let usableWidth = max(containerWidth - (CatalogCardLayoutMode.screenHorizontalPadding * GridSizingRules.horizontalPaddingMultiplier), 0)
        let availableColumnCount = Int(floor((usableWidth + base.spacing) / (referenceCardWidth + base.spacing)))
        let columnCount = min(max(availableColumnCount, base.columnCount), maxColumnCount)

        return GridMetrics(
            columnCount: columnCount,
            spacing: base.spacing
        )
    }

    func cardMetrics(forCardWidth cardWidth: CGFloat) -> CardMetrics {
        let base = cardMetrics
        let widthGrowth = max((cardWidth / referenceCardWidth) - CardMetricScaleLimits.baselineScale, 0)
        let heightScale = min(
            CardMetricScaleLimits.baselineScale + (widthGrowth * CardMetricScaleLimits.heightGrowthMultiplier),
            CardMetricScaleLimits.maxHeightScale
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
            cornerRadius: base.cornerRadius * cornerRadiusScale
        )
    }

    func cardWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        let currentMetrics = gridMetrics(forContainerWidth: containerWidth)
        let totalSpacing = currentMetrics.spacing * CGFloat(max(currentMetrics.columnCount - 1, 0))
        let usableWidth = max(containerWidth - (CatalogCardLayoutMode.screenHorizontalPadding * GridSizingRules.horizontalPaddingMultiplier) - totalSpacing, 0)
        return floor(usableWidth / CGFloat(currentMetrics.columnCount))
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
}

private enum CardMetricScaleLimits {
    static let baselineScale: CGFloat = 1
    static let heightGrowthMultiplier: CGFloat = 0.35
    static let paddingGrowthMultiplier: CGFloat = 0.16
    static let contentSpacingGrowthMultiplier: CGFloat = 0.14
    static let cornerRadiusGrowthMultiplier: CGFloat = 0.12
    static let maxHeightScale: CGFloat = 1.18
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
