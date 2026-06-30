struct CollectionSharingState {
    var isShared: Bool
    var currentUserRole: CollectionAccessRole
    var participants: [CollectionParticipant]

    init(
        currentUserRole: CollectionAccessRole,
        participants: [CollectionParticipant]
    ) {
        self.currentUserRole = currentUserRole
        self.participants = participants
        self.isShared = participants.contains {
            !$0.isCurrentUser && $0.role != .owner && $0.acceptanceStatus != .removed
        }
    }

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
        currentUserRole: .owner,
        participants: []
    )
}
