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

enum CatalogBackgrounds {
    static func app(scheme: ColorScheme) -> LinearGradient {
        tinted(.orange, scheme: scheme, strength: .weak)
    }

    static func collection(_ tint: Color, scheme: ColorScheme) -> LinearGradient {
        tinted(tint, scheme: scheme, strength: .medium)
    }

    static func collectionPreview(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.55),
                tint.opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func tinted(
        _ tint: Color,
        scheme: ColorScheme,
        strength: TintStrength
    ) -> LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(strength.opacity),
                scheme == .dark
                    ? Color.black.opacity(0.92)
                    : Color.white.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private enum TintStrength {
        case weak
        case medium

        var opacity: Double {
            switch self {
            case .weak: 0.10
            case .medium: 0.18
            }
        }
    }
}