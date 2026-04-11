import Foundation

enum CollectionRole: String, Hashable {
    case owner
    case editor
    case viewer

    var shortLabel: String {
        switch self {
        case .owner:
            return "owner"
        case .editor:
            return "editor"
        case .viewer:
            return "viewer"
        }
    }

    var title: String {
        switch self {
        case .owner:
            return "Владелец"
        case .editor:
            return "Редактор"
        case .viewer:
            return "Наблюдатель"
        }
    }
}

struct Collaborator: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let role: CollectionRole
    let isCurrentUser: Bool
}
