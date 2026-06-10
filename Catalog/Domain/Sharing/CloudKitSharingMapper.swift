import CloudKit
import CryptoKit
import Foundation

enum CloudKitSharingMapper {
    static func collectionParticipant(
        from participant: CKShare.Participant,
        collectionID: UUID
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
            role: role(for: participant)
        )
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

    static func displayName(for participant: CKShare.Participant) -> String? {
        guard let nameComponents = participant.userIdentity.nameComponents else {
            return nil
        }

        let displayName = PersonNameComponentsFormatter().string(from: nameComponents)
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
