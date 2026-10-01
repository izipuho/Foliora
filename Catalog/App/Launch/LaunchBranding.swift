import SwiftUI

/// Brand values shared by the launch storyboard and the SwiftUI launch sequence.
///
/// The launch storyboard (`LaunchScreen.storyboard`) is drawn by the system before
/// the app runs, so `Layout` repeats its constraints. Both follow the Figma launch
/// screens in `design/launch-screen`; `scripts/generate-launch-assets.py` prints
/// these numbers. Keep the storyboard and `Layout` in sync, or the handoff from the
/// system launch screen to the splash shows a jump.
enum LaunchBranding {
    enum Layout {
        /// From the top of the safe area to the top of `LaunchWordmark`.
        static let wordmarkTop: CGFloat = 65 + 1 / 3
        /// From the bottom of `LaunchWordmark` to the top of `LaunchSubtitle`.
        static let subtitleSpacing: CGFloat = 26 + 1 / 3
        /// The visible circle inside the `LaunchMedallion` canvas, which also holds its glow.
        static let medallionDiameter: CGFloat = 266 + 2 / 3
        /// The natural heights of `ArcLeft` and `ArcRight`; both span the full width.
        static let leftArcHeight: CGFloat = 274
        static let rightArcHeight: CGFloat = 148
    }

    /// Spoken in place of the wordmark and product name images.
    static var accessibilityName: String {
        "Foliora \(productName)"
    }

    private static var productName: String {
        switch CollectionAppLink.currentAppKind {
        case .bells:
            "Bells"
        case .books:
            "Books"
        }
    }

    /// How the medallion glyph swings while the app is loading.
    struct GlyphMotion {
        /// The point the glyph rotates around, in the medallion canvas's unit coordinates.
        let pivot: UnitPoint
        /// Scales the shared swing angles.
        let amplitude: Double
    }

    static var glyphMotion: GlyphMotion {
        switch CollectionAppLink.currentAppKind {
        case .bells:
            // The bell hangs from its top.
            GlyphMotion(pivot: UnitPoint(x: 0.5, y: 0.225), amplitude: 1)
        case .books:
            // The books rock on the shelf.
            GlyphMotion(pivot: UnitPoint(x: 0.5, y: 0.73), amplitude: 0.4)
        }
    }

    /// A random greeting from the app's `GreetingsKeys.plist`, addressed by name when known.
    static func randomGreeting() -> String {
        guard let url = Bundle.main.url(forResource: "GreetingsKeys", withExtension: "plist"),
              let suffixes = NSArray(contentsOf: url) as? [String],
              let suffix = suffixes.randomElement()
        else {
            return ""
        }

        let name = ProfileSettings.displayName.map {
            String.localizedStringWithFormat(String(localized: "splash.greeting_name"), $0)
        } ?? ""
        let greetingKey = "splash.greeting.\(suffix)"
        return String.localizedStringWithFormat(
            String(localized: LocalizedStringResource(stringLiteral: greetingKey)),
            name
        )
    }
}
