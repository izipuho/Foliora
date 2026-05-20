import SwiftUI

public enum DesignSystem {}

public enum CatalogCornerRadii {
    public static let hero: CGFloat = 28
    public static let section: CGFloat = 24
    public static let medium: CGFloat = 18
    public static let tile: CGFloat = 16
    public static let highlight: CGFloat = 14
    public static let thumbnail: CGFloat = 12
}

public enum CatalogLayoutInsets {
    public static let screen: CGFloat = 8
    public static let overlay: CGFloat = 8
}

public enum CatalogSpacing {
    public static let micro: CGFloat = 4
    public static let compact: CGFloat = 6
    public static let regular: CGFloat = 12
    public static let section: CGFloat = 24
}

public enum CatalogSemanticColors {
    public static let separator = Color(uiColor: .separator)
    public static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    public static let groupedSurfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    public static let fill = Color(uiColor: .systemFill)
    public static let secondaryFill = Color(uiColor: .secondarySystemFill)
    public static let tertiaryFill = Color(uiColor: .tertiarySystemFill)
    public static let quaternaryFill = Color(uiColor: .quaternarySystemFill)
    public static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
}

public struct CatalogShadowStyle: Sendable {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    public init(color: Color, radius: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.y = y
    }
}

public enum CatalogElevation {
    public static let card = CatalogShadowStyle(
        color: Color(uiColor: .separator).opacity(0.22),
        radius: 12,
        y: 6
    )

    public static let floatingCard = CatalogShadowStyle(
        color: Color(uiColor: .separator).opacity(0.22),
        radius: 14,
        y: 8
    )

    public static let collectionCard = CatalogShadowStyle(
        color: Color(uiColor: .separator).opacity(0.22),
        radius: 16,
        y: 8
    )

    public static let detailSection = CatalogShadowStyle(
        color: Color(uiColor: .separator).opacity(0.22),
        radius: 10,
        y: 4
    )

    public static func highlightedDetailSection(tint: Color) -> CatalogShadowStyle {
        CatalogShadowStyle(
            color: tint.opacity(0.14),
            radius: 14,
            y: 4
        )
    }
}

public struct CatalogListRowCard: View {
    private let systemImage: String
    private let title: String
    private let subtitle: String?

    public init(systemImage: String, title: String, subtitle: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

public struct CatalogSettingsRow: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
    }
}

public enum CatalogPillPadding {
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

public struct TagFlowLayout: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + rowHeight
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

public extension View {
    func catalogShadow(_ style: CatalogShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }

    func catalogPillPadding(_ style: CatalogPillPadding) -> some View {
        padding(.horizontal, style.horizontal)
            .padding(.vertical, style.vertical)
    }

    func catalogGlassPanel(
        cornerRadius: CGFloat = CatalogCornerRadii.section,
        strokeColor: Color = Color.white.opacity(0.32)
    ) -> some View {
        padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}
