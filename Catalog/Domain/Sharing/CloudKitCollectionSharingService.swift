import CloudKit
import Foundation

protocol CollectionSharingService: Sendable {
    func fetchShare(for collectionID: UUID) async throws -> CKShare?

    func sharingState(
        for collectionID: UUID
    ) async throws -> CollectionSharingState
}

final class CloudKitCollectionSharingService: CollectionSharingService, @unchecked Sendable {
    private let container: CKContainer
    private let privateDatabase: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitConfiguration.default.containerIdentifier)) {
        self.container = container
        self.privateDatabase = container.privateCloudDatabase
    }

    func fetchShare(for collectionID: UUID) async throws -> CKShare? {
        let predicate = NSPredicate(
            format: "%K == %@",
            Field.collectionID,
            collectionID.uuidString
        )
        let query = CKQuery(
            recordType: RecordType.sharedCollection,
            predicate: predicate
        )
        let result = try await privateDatabase.records(
            matching: query,
            resultsLimit: 1
        )

        guard let firstMatch = result.matchResults.first else {
            return nil
        }

        let record = try firstMatch.1.get()

        guard let shareReference = record.share else {
            return nil
        }

        return try await privateDatabase.record(
            for: shareReference.recordID
        ) as? CKShare
    }

    func sharingState(
        for collectionID: UUID
    ) async throws -> CollectionSharingState {
        guard let share = try await fetchShare(for: collectionID) else {
            return CollectionSharingState(
                isShared: false,
                currentUserRole: .owner,
                participants: []
            )
        }

        let participants = share.participants.map {
            CloudKitSharingMapper.collectionParticipant(
                from: $0,
                collectionID: collectionID
            )
        }

        let currentUserRole = share.currentUserParticipant.map {
            CloudKitSharingMapper.collectionParticipant(
                from: $0,
                collectionID: collectionID
            ).role
        } ?? .owner

        return CollectionSharingState(
            isShared: true,
            currentUserRole: currentUserRole,
            participants: participants
        )
    }
}

private extension CloudKitCollectionSharingService {
    enum RecordType {
        static let sharedCollection = "SharedCollection"
    }

    enum Field {
        static let collectionID = "collectionID"
    }
}
