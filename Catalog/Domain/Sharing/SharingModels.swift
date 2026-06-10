import Foundation

enum CollectionAccessRole: String, Identifiable, Hashable, Codable {
    case owner
    case contributor
    case viewer

    var id: String { rawValue }
}

enum CollectionParticipantStatus: String, Identifiable, Hashable, Codable {
    case current
    case invited
    case removed
    case unknown

    var id: String { rawValue }
}

struct CollectionParticipant: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    let cloudKitParticipantID: String?
    let displayName: String?
    var role: CollectionAccessRole
    var status: CollectionParticipantStatus
}
