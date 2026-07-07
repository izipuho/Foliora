import SwiftUI

enum CatalogCardAccessory: Hashable, Identifiable {
    case chip(String)
    case label(text: String, systemImage: String)
    case badge(CatalogCardBadge)

    var id: Self {
        self
    }
}

enum CatalogCardBadge: Hashable, Identifiable {
    case shared
    case warning
    case success
    case error
    case custom(String)

    var id: Self {
        self
    }
}

struct CatalogCardContentStyle {
    struct TitleBlockStyle {
        let titleFont: Font
        let titleLineLimit: Int
        let showsSubtitle: Bool
        let subtitleFont: Font
        let subtitleLineLimit: Int
        let spacing: CGFloat
    }

    struct AccessoryRowStyle {
        let spacing: CGFloat
        let font: Font
    }

    let title: TitleBlockStyle?
    let accessoryRow: AccessoryRowStyle?

    static let covers = CatalogCardContentStyle(
        title: TitleBlockStyle(
            titleFont: .caption.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: false,
            subtitleFont: .caption2,
            subtitleLineLimit: 1,
            spacing: CatalogMetrics.Spacing.xxs
        ),
        accessoryRow: nil
    )

    static let mini = CatalogCardContentStyle(
        title: TitleBlockStyle(
            titleFont: .subheadline.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: false,
            subtitleFont: .caption2,
            subtitleLineLimit: 1,
            spacing: CatalogMetrics.Spacing.xs
        ),
        accessoryRow: AccessoryRowStyle(
            spacing: 8,
            font: .caption2.weight(.semibold)
        )
    )

    static let compact = CatalogCardContentStyle(
        title: TitleBlockStyle(
            titleFont: .headline.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: true,
            subtitleFont: .caption,
            subtitleLineLimit: 2,
            spacing: CatalogMetrics.Spacing.xs
        ),
        accessoryRow: AccessoryRowStyle(
            spacing: 8,
            font: .caption2.weight(.semibold)
        )
    )

    static let wide = CatalogCardContentStyle(
        title: TitleBlockStyle(
            titleFont: .headline.weight(.semibold),
            titleLineLimit: 2,
            showsSubtitle: true,
            subtitleFont: .caption,
            subtitleLineLimit: 2,
            spacing: CatalogMetrics.Spacing.xs
        ),
        accessoryRow: AccessoryRowStyle(
            spacing: 8,
            font: .caption2.weight(.semibold)
        )
    )

    static let showcase = CatalogCardContentStyle(
        title: TitleBlockStyle(
            titleFont: .title.weight(.semibold),
            titleLineLimit: 3,
            showsSubtitle: true,
            subtitleFont: .body,
            subtitleLineLimit: 2,
            spacing: CatalogMetrics.Spacing.xs
        ),
        accessoryRow: AccessoryRowStyle(
            spacing: 8,
            font: .caption2.weight(.semibold)
        )
    )

    static func style(for layoutMode: CatalogCardLayoutMode) -> CatalogCardContentStyle {
        switch layoutMode {
        case .covers:
            return .covers
        case .mini:
            return .mini
        case .compact:
            return .compact
        case .wide:
            return .wide
        case .showcase:
            return .showcase
        }
    }
}

struct CatalogCardAccessoryRow: View {
    let accessories: [CatalogCardAccessory]
    let style: CatalogCardContentStyle.AccessoryRowStyle
    let bright: Bool

    var body: some View {
        HStack(spacing: style.spacing) {
            ForEach(accessories) { accessory in
                switch accessory {
                case .chip(let text):
                    capsuleText(text)
                case .label(let text, let systemImage):
                    Label(text, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(style.font)
                        .lineLimit(1)
                        .foregroundStyle(foregroundStyle)
                case .badge(let badge):
                    capsuleText(badge.title)
                }
            }
        }
    }

    private func capsuleText(_ text: String) -> some View {
        Text(text)
            .font(style.font)
            .lineLimit(1)
            .foregroundStyle(foregroundStyle)
            .catalogSurfaceCapsule()
    }

    private var foregroundStyle: Color {
        bright ? CatalogMediaContrast.onMediaPrimary : .secondary
    }
}

private extension CatalogCardBadge {
    var title: String {
        switch self {
        case .shared:
            return "Shared"
        case .warning:
            return "Warning"
        case .success:
            return "Success"
        case .error:
            return "Error"
        case .custom(let text):
            return text
        }
    }
}
