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

public extension View {
    func catalogShadow(_ style: CatalogShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }
}
