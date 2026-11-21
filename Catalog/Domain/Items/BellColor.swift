import Foundation

/// Describes the visible color of a bell, independently of its material.
enum BellColor: String, CaseIterable, Hashable, Identifiable, Codable, Sendable {
    case white
    case black
    case gray
    case silver
    case gold
    case bronze
    case brown
    case red
    case orange
    case yellow
    case green
    case turquoise
    case blue
    case purple
    case pink
    case multicolored
    case transparent

    var id: String { rawValue }

    var displayName: String {
        String(localized: "enum.bell_color.\\(rawValue)")
    }
}
