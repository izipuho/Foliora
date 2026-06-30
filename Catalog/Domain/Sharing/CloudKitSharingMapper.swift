import CloudKit
import CryptoKit
import Foundation

enum CloudKitSharingMapper {
    static func collectionParticipant(
        from participant: CKShare.Participant,
        collectionID: UUID,
        isCurrentUser: Bool = false
    ) -> CollectionParticipant {
        let cloudKitParticipantID = cloudKitParticipantID(for: participant)
        let displayName = displayName(for: participant)

        return CollectionParticipant(
            id: stableUUID(from: participantIdentitySeed(
                participant,
                cloudKitParticipantID: cloudKitParticipantID,
                displayName: displayName
            )),
            collectionID: collectionID,
            cloudKitParticipantID: cloudKitParticipantID,
            displayName: displayName,
            role: role(for: participant),
            acceptanceStatus: acceptanceStatus(for: participant),
            isCurrentUser: isCurrentUser
        )
    }

    static func currentUserRole(from participants: [CollectionParticipant]) -> CollectionAccessRole {
        participants.first { $0.isCurrentUser }?.role ?? .viewer
    }
}

private extension CloudKitSharingMapper {
    static func role(for participant: CKShare.Participant) -> CollectionAccessRole {
        if participant.role == .owner {
            return .owner
        }

        if participant.permission == .readWrite {
            return .contributor
        }

        if participant.permission == .readOnly {
            return .viewer
        }

        return .viewer
    }

    static func acceptanceStatus(for participant: CKShare.Participant) -> CollectionParticipantAcceptanceStatus {
        switch participant.acceptanceStatus {
        case .accepted:
            return .accepted
        case .pending:
            return .pending
        case .removed:
            return .removed
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func displayName(for participant: CKShare.Participant) -> String? {
        guard let nameComponents = participant.userIdentity.nameComponents else {
            return participant.role == .owner ? String(localized: "collection.sharing.participant.you") : nil
        }

        let displayName = PersonNameComponentsFormatter().string(from: nameComponents)
        if displayName.isEmpty, participant.role == .owner {
            return String(localized: "collection.sharing.participant.you")
        }

        return displayName.isEmpty ? nil : displayName
    }

    static func cloudKitParticipantID(for participant: CKShare.Participant) -> String? {
        if let recordName = participant.userIdentity.userRecordID?.recordName,
           !recordName.isEmpty {
            return recordName
        }

        if let recordName = participant.userIdentity.lookupInfo?.userRecordID?.recordName,
           !recordName.isEmpty {
            return recordName
        }

        return nil
    }

    static func participantIdentitySeed(
        _ participant: CKShare.Participant,
        cloudKitParticipantID: String?,
        displayName: String?
    ) -> String {
        var components: [String] = []

        if let cloudKitParticipantID {
            components.append("cloudKitParticipantID:\(cloudKitParticipantID)")
        }

        if let emailAddress = participant.userIdentity.lookupInfo?.emailAddress,
           !emailAddress.isEmpty {
            components.append("email:\(emailAddress.lowercased())")
        }

        if let phoneNumber = participant.userIdentity.lookupInfo?.phoneNumber,
           !phoneNumber.isEmpty {
            components.append("phone:\(phoneNumber)")
        }

        if let displayName {
            components.append("displayName:\(displayName)")
        }

        components.append("role:\(participant.role)")
        components.append("permission:\(participant.permission)")
        components.append("acceptanceStatus:\(participant.acceptanceStatus)")

        return components.joined(separator: "|")
    }

    static func stableUUID(from seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))

        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15]
        ))
    }
}
