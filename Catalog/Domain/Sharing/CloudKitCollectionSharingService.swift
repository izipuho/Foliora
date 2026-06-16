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
        let persistentStore = try persistentStore(for: collection)

        let sharesBefore = try persistentContainer.fetchShares(matching: [collection.objectID])

        if let existingShare = sharesBefore[collection.objectID] {
            return try await savedShare(
                existingShare,
                title: title,
                objectID: collection.objectID,
                in: persistentStore
            )
        }

        let share = try await share(collection)

        return try await savedShare(
            share,
            title: title,
            objectID: collection.objectID,
            in: persistentStore
        )
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

    func savedShare(
        _ share: CKShare,
        title: String? = nil,
        objectID: NSManagedObjectID,
        in persistentStore: NSPersistentStore
    ) async throws -> CKShare {
        var needsPersisting = share.url == nil

        if let title, share[CKShare.SystemFieldKey.title] as? String != title {
            share[CKShare.SystemFieldKey.title] = title
            needsPersisting = true
        }

        if needsPersisting {
            _ = try await persistUpdatedShare(share, in: persistentStore)

            let sharesAfterPersist = try persistentContainer.fetchShares(matching: [objectID])
            let refetchedShare = sharesAfterPersist[objectID]

            guard let refetchedShare else {
                throw CloudKitCollectionSharingError.shareNotCreated
            }

            guard refetchedShare.url != nil else {
                throw CloudKitCollectionSharingError.shareURLUnavailable
            }

            return refetchedShare
        }

        guard share.url != nil else {
            throw CloudKitCollectionSharingError.shareURLUnavailable
        }

        return share
    }

    func persistUpdatedShare(_ share: CKShare, in persistentStore: NSPersistentStore) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            persistentContainer.persistUpdatedShare(share, in: persistentStore) { persistedShare, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let persistedShare {
                    continuation.resume(returning: persistedShare)
                } else {
                    continuation.resume(throwing: CloudKitCollectionSharingError.shareNotCreated)
                }
            }
        }
    }

    func persistentStore(for collection: NSManagedObject) throws -> NSPersistentStore {
        guard let persistentStore = collection.objectID.persistentStore else {
            throw CloudKitCollectionSharingError.persistentStoreNotFound
        }

        return persistentStore
    }
}

private enum CloudKitCollectionSharingError: LocalizedError {
    case collectionNotFound(UUID)
    case persistentStoreNotFound
    case shareNotCreated
    case shareURLUnavailable

    var errorDescription: String? {
        switch self {
        case .collectionNotFound(let collectionID):
            return "No CollectionEntity found for \(collectionID)."
        case .persistentStoreNotFound:
            return "No persistent store found for the shared collection."
        case .shareNotCreated:
            return "Core Data did not return a CloudKit share."
        case .shareURLUnavailable:
            return "Core Data did not return a saved CloudKit share URL."
        }
    }
}
