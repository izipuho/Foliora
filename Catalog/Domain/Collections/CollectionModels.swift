import Foundation
import SwiftUI

enum CollectionKind: String, CaseIterable, Hashable, Identifiable {
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
}

enum CollectionStatus: String, Hashable {
    case active
    case planned

    var label: String {
        switch self {
        case .active:
            return "Активна"
        case .planned:
            return "Следующая"
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

struct CollectionSummary: Identifiable, Hashable {
    let id: UUID
    let kind: CollectionKind
    let name: String
    let subtitle: String
    let itemCount: Int
    let collaboratorCount: Int
    let role: CollectionRole
    let status: CollectionStatus
    let sharingSummary: String
}
