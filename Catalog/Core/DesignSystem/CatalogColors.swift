import SwiftUI

enum CatalogSemanticColors {
    //static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    //static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    //static let groupedSurfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)

    //static let primaryLabel = Color(uiColor: .label)
    //static let secondaryLabel = Color(uiColor: .secondaryLabel)
    //static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

    //static let separator = Color(uiColor: .separator)
    //static let secondaryFill = Color(uiColor: .secondarySystemFill)

    static let success = Color.green
    static let destructive = Color.red
    static let info = Color.blue
}

enum CatalogMediaContrast {
    static let scrimClear = Color.black.opacity(0)
    static let scrimWeak = Color.black.opacity(0.10)
    static let scrimMedium = Color.black.opacity(0.22)
    static let scrimStrong = Color.black.opacity(0.32)

    static let glassFill = Color.white.opacity(0.16)
    static let glassStroke = Color.white.opacity(0.32)

    static let onMediaPrimary = Color.white
}