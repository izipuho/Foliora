struct CollectionSharingState {
    var isShared: Bool
    var currentUserRole: CollectionAccessRole
    var participants: [CollectionParticipant]

    var peopleParticipants: [CollectionParticipant] {
        participants.filter {
            $0.role == .owner || $0.acceptanceStatus == .accepted
        }
    }

    var invitedParticipants: [CollectionParticipant] {
        participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .pending
        }
    }

    var visibleParticipantsCount: Int {
        peopleParticipants.count
    }

    static let placeholder = CollectionSharingState(
        isShared: false,
        currentUserRole: .owner,
        participants: []
    )
}
