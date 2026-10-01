import SwiftUI

/// Brand values shared by the launch storyboard and the SwiftUI launch sequence.
///
/// The launch storyboard (`LaunchScreen.storyboard`) is drawn by the system before
/// the app runs, so these numbers repeat its constraints: keep both in sync, or the
/// handoff from the system launch screen to the splash shows a jump.
enum LaunchBranding {
    /// Sizes taken from `LaunchScreen.storyboard`, including its regular/regular variation.
    struct Metrics {
        let wordmarkSize: CGFloat
        let subtitleSize: CGFloat
        let medallionSide: CGFloat

        init(isRegular: Bool) {
            wordmarkSize = isRegular ? 100 : 80
            subtitleSize = isRegular ? 70 : 50
            medallionSide = isRegular ? 320 : 220
        }
    }

    /// The brand wordmark. It is a name, so it is never localized.
    static let wordmark = "Foliora"

    /// The product name shown under the wordmark once the splash takes over,
    /// localized: the name of the app's collection kind.
    static var productName: String {
        CollectionAppLink.currentAppKind.title
    }

    /// How the medallion glyph swings while the app is loading.
    struct GlyphMotion {
        /// The point the glyph rotates around, in the medallion's unit coordinates.
        let pivot: UnitPoint
        /// Scales the shared swing angles.
        let amplitude: Double
    }

    static var glyphMotion: GlyphMotion {
        switch CollectionAppLink.currentAppKind {
        case .bells:
            // The bell hangs from its top.
            GlyphMotion(pivot: UnitPoint(x: 0.5, y: 0.14), amplitude: 1)
        case .books:
            // The books rock on the shelf.
            GlyphMotion(pivot: UnitPoint(x: 0.5, y: 0.8), amplitude: 0.4)
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
