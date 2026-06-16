import Foundation

enum CollectionAccessRole: String, Identifiable, Hashable, Codable {
    case owner
    case contributor
    case viewer

    var id: String { rawValue }
}

enum CollectionParticipantAcceptanceStatus: String, Hashable, Codable {
    case accepted
    case pending
    case removed
    case unknown
}

struct CollectionParticipant: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    let cloudKitParticipantID: String?
    let displayName: String?
    var role: CollectionAccessRole
    let acceptanceStatus: CollectionParticipantAcceptanceStatus
    let isCurrentUser: Bool

    init(
        id: UUID,
        collectionID: UUID,
        cloudKitParticipantID: String?,
        displayName: String?,
        role: CollectionAccessRole,
        acceptanceStatus: CollectionParticipantAcceptanceStatus,
        isCurrentUser: Bool = false
    ) {
        self.id = id
        self.collectionID = collectionID
        self.cloudKitParticipantID = cloudKitParticipantID
        self.displayName = displayName
        self.role = role
        self.acceptanceStatus = acceptanceStatus
        self.isCurrentUser = isCurrentUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        collectionID = try container.decode(UUID.self, forKey: .collectionID)
        cloudKitParticipantID = try container.decodeIfPresent(String.self, forKey: .cloudKitParticipantID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        role = try container.decode(CollectionAccessRole.self, forKey: .role)
        acceptanceStatus = try container.decodeIfPresent(
            CollectionParticipantAcceptanceStatus.self,
            forKey: .acceptanceStatus
        ) ?? .unknown
        isCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
    }
}
