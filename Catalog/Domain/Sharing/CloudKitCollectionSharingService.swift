import CloudKit
import CoreData
import Foundation

protocol CollectionSharingService: Sendable {
    func fetchShare(for collectionID: UUID) async throws -> CKShare?

    func createShare(for collectionID: UUID, title: String) async throws -> CKShare

    func sharingState(
        for collectionID: UUID
    ) async throws -> CollectionSharingState
}

final class CloudKitCollectionSharingService: CollectionSharingService, @unchecked Sendable {
    private let persistentContainer: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext

    convenience init(container _: CKContainer = CKContainer.default()) {
        do {
            try self.init(persistentContainer: FolioraCoreDataStack.makeContainer())
        } catch {
            fatalError("Failed to create Core Data container for sharing: \(error)")
        }
    }

    init(persistentContainer: NSPersistentCloudKitContainer) {
        self.persistentContainer = persistentContainer
        self.context = persistentContainer.newBackgroundContext()
        self.context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    func fetchShare(for collectionID: UUID) async throws -> CKShare? {
        let collection = try await collectionEntity(for: collectionID)
        return try persistentContainer.fetchShares(matching: [collection.objectID])[collection.objectID]
    }

    func createShare(
        for collectionID: UUID,
        title: String
    ) async throws -> CKShare {
        let collection = try await collectionEntity(for: collectionID)

        if let existingShare = try persistentContainer.fetchShares(matching: [collection.objectID])[collection.objectID] {
            return existingShare
        }

        let share = try await share(collection)
        share[CKShare.SystemFieldKey.title] = title

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

        let currentUserParticipant = share.currentUserParticipant
        let participants = share.participants.map {
            CloudKitSharingMapper.collectionParticipant(
                from: $0,
                collectionID: collectionID,
                isCurrentUser: $0 == currentUserParticipant
            )
        }

        let currentUserRole = participants.first { $0.isCurrentUser }?.role ?? .viewer

        return CollectionSharingState(
            isShared: true,
            currentUserRole: currentUserRole,
            participants: participants
        )
    }
}

private extension CloudKitCollectionSharingService {
    func collectionEntity(for collectionID: UUID) async throws -> NSManagedObject {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", collectionID as NSUUID)

            guard let collection = try self.context.fetch(request).first else {
                throw CloudKitCollectionSharingError.collectionNotFound(collectionID)
            }

            return collection
        }
    }

    func share(_ collection: NSManagedObject) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            persistentContainer.share([collection], to: nil) { _, share, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let share {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: CloudKitCollectionSharingError.shareNotCreated)
                }
            }
        }
    }
}

private enum CloudKitCollectionSharingError: LocalizedError {
    case collectionNotFound(UUID)
    case shareNotCreated

    var errorDescription: String? {
        switch self {
        case .collectionNotFound(let collectionID):
            return "No CollectionEntity found for \(collectionID)."
        case .shareNotCreated:
            return "Core Data did not return a CloudKit share."
        }
    }
}
