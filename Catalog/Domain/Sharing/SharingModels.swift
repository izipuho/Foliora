import Foundation

private func SL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum CollectionRole: String, Hashable, Codable {
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
            return SL("enum.collection_role.owner")
        case .editor:
            return SL("enum.collection_role.editor")
        case .contributor:
            return SL("enum.collection_role.contributor")
        case .viewer:
            return SL("enum.collection_role.viewer")
        }
    }
}

enum MembershipStatus: String, Hashable, CaseIterable, Identifiable, Codable {
    case pending
    case active
    case revoked

    var id: String { rawValue }
}

struct Membership: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    let userID: String
    var role: CollectionRole
    var status: MembershipStatus
}

struct Collaborator: Identifiable, Hashable, Codable {
    let id: UUID
    let displayName: String
    let role: CollectionRole
    let isCurrentUser: Bool
}
