import CloudKit
import Foundation

protocol CollectionSharingService: Sendable {
    func fetchShare(for collectionID: UUID) async throws -> CKShare?

    func createShare(for collectionID: UUID) async throws -> CKShare

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
        guard let record = try await findCollectionRecord(for: collectionID),
              let shareReference = record.share else {
            return nil
        }

        return try await privateDatabase.record(
            for: shareReference.recordID
        ) as? CKShare
    }

    func findCollectionRecord(
        for collectionID: UUID
    ) async throws -> CKRecord? {
        let predicate = NSPredicate(
            format: "%K == %@",
            Field.collectionID,
            collectionID.uuidString
        )
        let query = CKQuery(
            recordType: RecordType.collectionEntity,
            predicate: predicate
        )
        let result = try await privateDatabase.records(
            matching: query,
            inZoneWith: Zone.swiftData,
            resultsLimit: 1
        )

        return try result.matchResults.first?.1.get()
    }

    func createShare(
        for collectionID: UUID
    ) async throws -> CKShare {
        guard let record = try await findCollectionRecord(for: collectionID) else {
            throw CloudKitCollectionSharingError.collectionRecordNotFound(collectionID)
        }

        let share = CKShare(rootRecord: record)
        try await save(records: [record, share])

        return share
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
        static let collectionEntity = "CD_CollectionEntity"
    }

    enum Field {
        static let collectionID = "CD_id"
    }

    enum Zone {
        static let swiftData = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
    }

    func save(records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(
                recordsToSave: records,
                recordIDsToDelete: nil
            )
            operation.savePolicy = .ifServerRecordUnchanged
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }

            privateDatabase.add(operation)
        }
    }
}

private enum CloudKitCollectionSharingError: LocalizedError {
    case collectionRecordNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .collectionRecordNotFound(let collectionID):
            return "No CD_CollectionEntity found for \(collectionID)."
        }
    }
}
