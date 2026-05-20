import SwiftUI

public enum DesignSystem {}

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

public extension View {
    func catalogShadow(_ style: CatalogShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }
}
