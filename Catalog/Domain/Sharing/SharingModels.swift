import Foundation

enum CollectionRole: String, Hashable, Codable {
    case owner
    case editor
    case contributor
    case viewer

    var shortLabel: String {
        title.lowercased(with: .autoupdatingCurrent)
    }

    var title: String {
        switch self {
        case .owner:
            return String(localized: "enum.collection_role.owner")
        case .editor:
            return String(localized: "enum.collection_role.editor")
        case .contributor:
            return String(localized: "enum.collection_role.contributor")
        case .viewer:
            return String(localized: "enum.collection_role.viewer")
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
