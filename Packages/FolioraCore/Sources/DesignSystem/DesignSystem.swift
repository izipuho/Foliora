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

public struct CatalogSettingsRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let trailing: Trailing

    public init(
        _ title: String,
        systemImage: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: CatalogSpacing.regular) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: CatalogSpacing.regular)

            trailing
        }
        .padding(.vertical, subtitle == nil ? 2 : 4)
    }
}

public extension CatalogSettingsRow where Trailing == EmptyView {
    init(_ title: String, systemImage: String, subtitle: String? = nil) {
        self.init(title, systemImage: systemImage, subtitle: subtitle) {
            EmptyView()
        }
    }
}

public struct CatalogDisclosureRow<Title: View, Subtitle: View, Trailing: View>: View {
    private let systemImage: String?
    private let showsChevron: Bool
    private let title: Title
    private let subtitle: Subtitle
    private let trailing: Trailing

    public init(
        systemImage: String? = nil,
        showsChevron: Bool = true,
        @ViewBuilder title: () -> Title,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.showsChevron = showsChevron
        self.title = title()
        self.subtitle = subtitle()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: CatalogSpacing.regular) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
                title
                    .foregroundStyle(.primary)

                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: CatalogSpacing.regular)

            trailing
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

public extension CatalogDisclosureRow where Title == Text, Subtitle == EmptyView, Trailing == Text {
    init(
        _ title: String,
        value: String,
        systemImage: String? = nil,
        showsChevron: Bool = true
    ) {
        self.init(systemImage: systemImage, showsChevron: showsChevron) {
            Text(title)
        } subtitle: {
            EmptyView()
        } trailing: {
            Text(value)
        }
    }
}

public struct CatalogDetailSection<Title: View, Content: View>: View {
    private let isHighlighted: Bool
    private let tint: Color
    private let title: Title
    private let content: Content

    public init(
        isHighlighted: Bool = false,
        tint: Color = .clear,
        @ViewBuilder title: () -> Title,
        @ViewBuilder content: () -> Content
    ) {
        self.isHighlighted = isHighlighted
        self.tint = tint
        self.title = title()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CatalogSpacing.regular) {
            title
                .font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous)
                .fill(isHighlighted ? AnyShapeStyle(tint.opacity(0.10)) : AnyShapeStyle(.ultraThinMaterial))
        )
        .catalogShadow(
            isHighlighted
                ? CatalogElevation.highlightedDetailSection(tint: tint)
                : CatalogElevation.detailSection
        )
    }
}

public extension CatalogDetailSection where Title == Text {
    init(
        _ title: String,
        isHighlighted: Bool = false,
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) {
        self.init(isHighlighted: isHighlighted, tint: tint) {
            Text(title)
        } content: {
            content()
        }
    }
}

public struct CatalogKeyValueRow<Label: View, Value: View>: View {
    private let label: Label
    private let value: Value

    public init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label()
        self.value = value()
    }

    public var body: some View {
        HStack {
            label
            Spacer(minLength: CatalogSpacing.regular)
            value
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

public extension CatalogKeyValueRow where Label == Text, Value == Text {
    init(_ label: String, value: String) {
        self.init {
            Text(label)
        } value: {
            Text(value)
        }
    }
}

public struct CatalogDashboardCard<Content: View>: View {
    private let width: CGFloat?
    private let content: Content

    public init(width: CGFloat? = 240, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    public var body: some View {
        content
            .padding()
            .frame(width: width, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8)
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

public struct CatalogPill<Content: View>: View {
    private let padding: CatalogPillPadding
    private let backgroundStyle: AnyShapeStyle
    private let foregroundStyle: AnyShapeStyle
    private let strokeStyle: AnyShapeStyle?
    private let strokeWidth: CGFloat
    private let shadowStyle: CatalogShadowStyle?
    private let content: Content

    public init(
        padding: CatalogPillPadding = .regular,
        backgroundStyle: AnyShapeStyle = AnyShapeStyle(.thinMaterial),
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary),
        strokeStyle: AnyShapeStyle? = nil,
        strokeWidth: CGFloat = 1,
        shadowStyle: CatalogShadowStyle? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.backgroundStyle = backgroundStyle
        self.foregroundStyle = foregroundStyle
        self.strokeStyle = strokeStyle
        self.strokeWidth = strokeWidth
        self.shadowStyle = shadowStyle
        self.content = content()
    }

    public var body: some View {
        content
            .catalogPillPadding(padding)
            .background(backgroundStyle, in: Capsule())
            .overlay {
                if let strokeStyle {
                    Capsule()
                        .stroke(strokeStyle, lineWidth: strokeWidth)
                }
            }
            .foregroundStyle(foregroundStyle)
            .shadow(
                color: shadowStyle?.color ?? .clear,
                radius: shadowStyle?.radius ?? 0,
                y: shadowStyle?.y ?? 0
            )
    }
}

public struct CatalogIconActionButton: View {
    private let systemImage: String
    private let tint: Color
    private let backgroundTint: Color
    private let role: ButtonRole?
    private let size: CGFloat
    private let action: () -> Void

    public init(
        systemImage: String,
        tint: Color = .primary,
        backgroundTint: Color = .clear,
        role: ButtonRole? = nil,
        size: CGFloat = 48,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.backgroundTint = backgroundTint
        self.role = role
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(backgroundTint)
                        }
                }
        }
        .buttonStyle(.plain)
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
