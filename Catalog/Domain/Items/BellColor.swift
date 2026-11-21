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
        switch self {
        case .white: String(localized: "enum.bell_color.white")
        case .black: String(localized: "enum.bell_color.black")
        case .gray: String(localized: "enum.bell_color.gray")
        case .silver: String(localized: "enum.bell_color.silver")
        case .gold: String(localized: "enum.bell_color.gold")
        case .bronze: String(localized: "enum.bell_color.bronze")
        case .brown: String(localized: "enum.bell_color.brown")
        case .red: String(localized: "enum.bell_color.red")
        case .orange: String(localized: "enum.bell_color.orange")
        case .yellow: String(localized: "enum.bell_color.yellow")
        case .green: String(localized: "enum.bell_color.green")
        case .turquoise: String(localized: "enum.bell_color.turquoise")
        case .blue: String(localized: "enum.bell_color.blue")
        case .purple: String(localized: "enum.bell_color.purple")
        case .pink: String(localized: "enum.bell_color.pink")
        case .multicolored: String(localized: "enum.bell_color.multicolored")
        case .transparent: String(localized: "enum.bell_color.transparent")
        }
    }
}
