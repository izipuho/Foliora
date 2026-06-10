struct CollectionSharingState {
    var isShared: Bool
    var currentUserRole: CollectionAccessRole
    var participants: [CollectionParticipant]

    static let placeholder = CollectionSharingState(
        isShared: false,
        currentUserRole: .owner,
        participants: []
    )
}
