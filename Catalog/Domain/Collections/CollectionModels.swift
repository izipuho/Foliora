import Foundation
import SwiftUI

private func CL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct Home: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var notes: String
}

struct Location: Identifiable, Hashable, Codable {
    let id: UUID
    let homeID: UUID
    var parentLocationID: UUID?
    var kind: LocationKind
    var name: String
    var notes: String
}

struct Collection: Identifiable, Hashable, Codable {
    let id: UUID
    let homeID: UUID
    var kind: CollectionKind
    var title: String
    var notes: String
    var backgroundStyle: CollectionBackgroundStyle

    init(
        id: UUID,
        homeID: UUID,
        kind: CollectionKind,
        title: String,
        notes: String,
        backgroundStyle: CollectionBackgroundStyle = .amber
    ) {
        self.id = id
        self.homeID = homeID
        self.kind = kind
        self.title = title
        self.notes = notes
        self.backgroundStyle = backgroundStyle
    }

    enum CodingKeys: String, CodingKey {
        case id
        case homeID
        case kind
        case title
        case notes
        case backgroundStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeID = try container.decode(UUID.self, forKey: .homeID)
        kind = try container.decode(CollectionKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        backgroundStyle = try container.decodeIfPresent(CollectionBackgroundStyle.self, forKey: .backgroundStyle) ?? .amber
    }
}

enum LocationKind: String, CaseIterable, Hashable, Identifiable, Codable {
    case floor
    case room
    case cabinet
    case shelf
    case box

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floor:
            return CL("enum.location_kind.floor")
        case .room:
            return CL("enum.location_kind.room")
        case .cabinet:
            return CL("enum.location_kind.cabinet")
        case .shelf:
            return CL("enum.location_kind.shelf")
        case .box:
            return CL("enum.location_kind.box")
        }
    }
}

enum CollectionKind: String, CaseIterable, Hashable, Identifiable, Codable {
    case bells
    case books

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bells:
            return "Колокольчики"
        case .books:
            return "Книги"
        }
    }

    var systemImage: String {
        switch self {
        case .bells:
            return "bell.fill"
        case .books:
            return "books.vertical.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .bells:
            return Color(red: 0.61, green: 0.35, blue: 0.14)
        case .books:
            return Color(red: 0.10, green: 0.39, blue: 0.33)
        }
    }

    func countLabel(for count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let key: String

        switch self {
        case .bells:
            key = "collection.count.bells"
        case .books:
            key = "collection.count.books"
        }

        let format = NSLocalizedString(key, comment: "Collection item count")
        return String(format: format, locale: locale, count)
    }
}

enum CollectionStatus: String, Hashable, Codable {
    case active
    case planned

    var label: String {
        switch self {
        case .active:
            return CL("enum.collection_status.active")
        case .planned:
            return CL("enum.collection_status.planned")
        }
    }

    var badgeColor: Color {
        switch self {
        case .active:
            return Color(red: 0.14, green: 0.48, blue: 0.27)
        case .planned:
            return Color(red: 0.16, green: 0.34, blue: 0.64)
        }
    }
}

struct CollectionSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let homeID: UUID
    let kind: CollectionKind
    let name: String
    let subtitle: String
    let backgroundStyle: CollectionBackgroundStyle
    let itemCount: Int
    let collaboratorCount: Int
    let role: CollectionRole
    let status: CollectionStatus
    let sharingSummary: String
}

enum CollectionBackgroundStyle: String, CaseIterable, Hashable, Identifiable, Codable {
    case amber
    case sky
    case mint
    case rose
    case slate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amber:
            return "Amber"
        case .sky:
            return "Sky"
        case .mint:
            return "Mint"
        case .rose:
            return "Rose"
        case .slate:
            return "Slate"
        }
    }

    var colors: [Color] {
        switch self {
        case .amber:
            return [
                Color(red: 0.99, green: 0.96, blue: 0.87),
                Color(red: 0.95, green: 0.86, blue: 0.66)
            ]
        case .sky:
            return [
                Color(red: 0.91, green: 0.97, blue: 1.0),
                Color(red: 0.73, green: 0.86, blue: 0.98)
            ]
        case .mint:
            return [
                Color(red: 0.92, green: 0.98, blue: 0.94),
                Color(red: 0.74, green: 0.90, blue: 0.82)
            ]
        case .rose:
            return [
                Color(red: 0.99, green: 0.93, blue: 0.94),
                Color(red: 0.95, green: 0.78, blue: 0.82)
            ]
        case .slate:
            return [
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.80, green: 0.85, blue: 0.92)
            ]
        }
    }

    var screenColors: [Color] {
        switch self {
        case .amber:
            return [
                Color(red: 0.98, green: 0.96, blue: 0.90),
                Color(red: 0.95, green: 0.91, blue: 0.82)
            ]
        case .sky:
            return [
                Color(red: 0.93, green: 0.97, blue: 1.0),
                Color(red: 0.84, green: 0.91, blue: 0.99)
            ]
        case .mint:
            return [
                Color(red: 0.94, green: 0.99, blue: 0.95),
                Color(red: 0.84, green: 0.94, blue: 0.88)
            ]
        case .rose:
            return [
                Color(red: 0.99, green: 0.95, blue: 0.96),
                Color(red: 0.96, green: 0.86, blue: 0.89)
            ]
        case .slate:
            return [
                Color(red: 0.95, green: 0.96, blue: 0.99),
                Color(red: 0.88, green: 0.90, blue: 0.95)
            ]
        }
    }

    var accentColor: Color {
        switch self {
        case .amber:
            return Color(red: 0.72, green: 0.45, blue: 0.16)
        case .sky:
            return Color(red: 0.20, green: 0.49, blue: 0.81)
        case .mint:
            return Color(red: 0.18, green: 0.53, blue: 0.39)
        case .rose:
            return Color(red: 0.76, green: 0.35, blue: 0.48)
        case .slate:
            return Color(red: 0.33, green: 0.41, blue: 0.58)
        }
    }
}
