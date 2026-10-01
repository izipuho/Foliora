import CloudKit
import CoreData
import Foundation
import UIKit

/// Defines the interface for collection sharing service implementations.
protocol CollectionSharingService: Sendable {
    func fetchShare(for collectionID: UUID) async throws -> (share: CKShare, container: CKContainer)?

    func localSharingReadiness(for collectionID: UUID) async throws -> (isReady: Bool, reasons: [String])

    func createShare(for collectionID: UUID, title: String) async throws -> (share: CKShare, container: CKContainer)

    func sharingState(
        for collectionID: UUID
    ) async throws -> CollectionSharingState
}

/// Provides cloud kit collection sharing service operations.
final class CloudKitCollectionSharingService: CollectionSharingService, @unchecked Sendable {
    private let persistentContainer: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext

    init(persistentContainer: NSPersistentCloudKitContainer) {
        self.persistentContainer = persistentContainer
        self.context = persistentContainer.newBackgroundContext()
        self.context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    func fetchShare(for collectionID: UUID) async throws -> (share: CKShare, container: CKContainer)? {
        do {
            let objectID = try await collectionObjectID(for: collectionID)
            guard let share = try persistentContainer.fetchShares(matching: [objectID])[objectID] else {
                return nil
            }
            guard let containerIdentifier = FolioraCoreDataStack.cloudKitContainerIdentifier(from: persistentContainer) else {
                throw CloudKitCollectionSharingError.shareNotCreated
            }
            return (share: share, container: CKContainer(identifier: containerIdentifier))
        } catch {
            throw error
        }
    }

    func localSharingReadiness(for collectionID: UUID) async throws -> (isReady: Bool, reasons: [String]) {
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", collectionID as NSUUID)

            guard let collection = try self.context.fetch(request).first else {
                throw CloudKitCollectionSharingError.collectionNotFound(collectionID)
            }

            let hasPermanentObjectID = !collection.objectID.isTemporaryID
            let hasPersistentStore = collection.objectID.persistentStore != nil
            let isNotInserted = !collection.isInserted
            let isNotDeleted = !collection.isDeleted
            let hasNoChanges = !collection.hasChanges

            let isReady = hasPermanentObjectID
                && hasPersistentStore
                && isNotInserted
                && isNotDeleted
                && hasNoChanges

            var reasons: [String] = []
            if !isReady {
                if !hasPermanentObjectID { reasons.append("temporaryObjectID") }
                if !hasPersistentStore { reasons.append("missingPersistentStore") }
                if !isNotInserted { reasons.append("inserted") }
                if !isNotDeleted { reasons.append("deleted") }
                if !hasNoChanges { reasons.append("hasChanges") }
            }

            return (isReady, reasons)
        }
    }

    func createShare(
        for collectionID: UUID,
        title: String
    ) async throws -> (share: CKShare, container: CKContainer) {
        do {
            let objectID = try await collectionObjectID(for: collectionID)
            let persistentStore = try persistentStore(for: objectID)

            let sharesBefore: [NSManagedObjectID: CKShare]
            do {
                sharesBefore = try persistentContainer.fetchShares(matching: [objectID])
            } catch {
                throw error
            }
            let existingShare = sharesBefore[objectID]

            if let existingShare {
                let share = try await savedShare(
                    existingShare,
                    title: title,
                    thumbnailImageData: shareThumbnailImageData(),
                    objectID: objectID,
                    in: persistentStore
                )
                guard let containerIdentifier = FolioraCoreDataStack.cloudKitContainerIdentifier(from: persistentContainer) else {
                    throw CloudKitCollectionSharingError.shareNotCreated
                }
                return (share: share, container: CKContainer(identifier: containerIdentifier))
            }

            try await prepareForSharing(objectID)
            let sharedCollection = try await share(objectID)

            let savedShare = try await savedShare(
                sharedCollection.share,
                title: title,
                thumbnailImageData: shareThumbnailImageData(),
                objectID: objectID,
                in: persistentStore
            )
            return (share: savedShare, container: sharedCollection.container)
        } catch {
            throw error
        }
    }

    func sharingState(
        for collectionID: UUID
    ) async throws -> CollectionSharingState {
        guard let share = try await fetchShare(for: collectionID)?.share else {
            return CollectionSharingState(
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
            currentUserRole: currentUserRole,
            participants: participants
        )
    }
}

private extension CloudKitCollectionSharingService {
    func collectionObjectID(for collectionID: UUID) async throws -> NSManagedObjectID {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", collectionID as NSUUID)

            guard let collection = try self.context.fetch(request).first else {
                throw CloudKitCollectionSharingError.collectionNotFound(collectionID)
            }

            return collection.objectID
        }
    }

    func share(_ objectID: NSManagedObjectID) async throws -> (share: CKShare, container: CKContainer) {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let collection = try self.context.existingObject(with: objectID)
                    self.persistentContainer.share([collection], to: nil) { _, share, container, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        if let share, let container {
                            continuation.resume(returning: (share: share, container: container))
                        } else {
                            continuation.resume(throwing: CloudKitCollectionSharingError.shareNotCreated)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func prepareForSharing(_ objectID: NSManagedObjectID) async throws {
        do {
            try await context.perform {
                let collection = try self.context.existingObject(with: objectID)

                if let home = collection.value(forKey: "home") as? NSManagedObject {
                    collection.setValue(home.value(forKey: "id"), forKey: "homeID")
                    collection.setValue(home.value(forKey: "name"), forKey: "homeName")
                    collection.setValue(home.value(forKey: "iconName"), forKey: "homeIconName")
                }

                collection.setValue(nil, forKey: "home")

                if self.context.hasChanges {
                    try self.context.save()
                }
            }
        } catch {
            throw error
        }
    }

    func normalizedShareTitle(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func needsTitleUpdate(_ share: CKShare, title: String) -> Bool {
        let newTitle = normalizedShareTitle(title)
        guard !newTitle.isEmpty else { return false }

        let currentTitle = normalizedShareTitle(share[CKShare.SystemFieldKey.title] as? String)
        return currentTitle != newTitle
    }

    func needsThumbnailUpdate(_ share: CKShare, thumbnailImageData: Data) -> Bool {
        let currentThumbnailImageData = share[CKShare.SystemFieldKey.thumbnailImageData] as? Data
        return currentThumbnailImageData != thumbnailImageData
    }

    /// The thumbnail of a share invitation: the app medallion, as on the launch screen.
    ///
    /// Always the light variant, since the invitation is seen on any background, and
    /// scaled to 512 px, since the image is stored in the share record.
    func shareThumbnailImageData() -> Data? {
        let light = UITraitCollection(userInterfaceStyle: .light)
        guard let medallion = UIImage(named: "LaunchMedallion", in: .main, compatibleWith: light) else {
            return nil
        }

        let side: CGFloat = 512
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .pngData { _ in
                medallion.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
    }

    func savedShare(
        _ share: CKShare,
        title: String? = nil,
        thumbnailImageData: Data? = nil,
        objectID: NSManagedObjectID,
        in persistentStore: NSPersistentStore
    ) async throws -> CKShare {
        var needsPersisting = share.url == nil

        if let title, needsTitleUpdate(share, title: title) {
            share[CKShare.SystemFieldKey.title] = title
            needsPersisting = true
        }

        if let thumbnailImageData, needsThumbnailUpdate(share, thumbnailImageData: thumbnailImageData) {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailImageData
            needsPersisting = true
        }

        if needsPersisting {
            let persistedShare = try await persistUpdatedShare(
                share,
                in: persistentStore
            )

            guard persistedShare.url != nil else {
                throw CloudKitCollectionSharingError.shareURLUnavailable
            }

            return share
        }

        guard share.url != nil else {
            throw CloudKitCollectionSharingError.shareURLUnavailable
        }

        return share
    }

    func persistUpdatedShare(_ share: CKShare, in persistentStore: NSPersistentStore) async throws -> CKShare {
        do {
            let persistedShare: CKShare = try await withCheckedThrowingContinuation { continuation in
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
            return persistedShare
        } catch {
            throw error
        }
    }

    func persistentStore(for objectID: NSManagedObjectID) throws -> NSPersistentStore {
        guard let persistentStore = objectID.persistentStore else {
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
            return "Коллекция еще не загружена в iCloud. Попробуйте немного позже."
        }
    }
}
