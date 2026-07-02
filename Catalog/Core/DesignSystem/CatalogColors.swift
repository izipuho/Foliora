import SwiftUI

enum CatalogSemanticColors {
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