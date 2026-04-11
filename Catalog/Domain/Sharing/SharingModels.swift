import Foundation

enum CollectionRole: String, Hashable {
    case owner
    case editor
    case contributor
    case viewer

    var shortLabel: String {
        switch self {
        case .owner:
            return "owner"
        case .editor:
            return "editor"
        case .contributor:
            return "contributor"
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
        case .contributor:
            return "Контрибьютор"
        case .viewer:
            return "Наблюдатель"
        }
    }
}

enum MembershipStatus: String, Hashable, CaseIterable, Identifiable {
    case pending
    case active
    case revoked

    var id: String { rawValue }
}

struct Membership: Identifiable, Hashable {
    let id: UUID
    let collectionID: UUID
    let userID: String
    var role: CollectionRole
    var status: MembershipStatus
}

struct Collaborator: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let role: CollectionRole
    let isCurrentUser: Bool
}
