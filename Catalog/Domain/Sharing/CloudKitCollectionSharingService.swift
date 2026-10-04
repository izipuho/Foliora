import CloudKit
import CoreData
import Foundation
import UIKit

/// Defines the interface for collection sharing service implementations.
protocol CollectionSharingService: Sendable {
    /// Returns the collection's share for the system sharing screen, creating it for a collection that is not shared yet.
    func createShare(for collectionID: UUID, title: String) async throws -> (share: CKShare, container: CKContainer)

    /// Stores the share after the system sharing screen changed it.
    ///
    /// Core Data does not pick up the changes the system sharing screen makes on its own.
    func persistUpdatedShare(_ share: CKShare, for collectionID: UUID) async throws

    /// Deletes the collection's share zone with everything in it.
    ///
    /// For the owner this deletes the shared collection for everyone. For a participant it leaves the
    /// share and removes the collection from this device.
    func purgeSharedCollection(for collectionID: UUID) async throws

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

    func createShare(
        for collectionID: UUID,
        title: String
    ) async throws -> (share: CKShare, container: CKContainer) {
        let objectID = try await collectionObjectID(for: collectionID)
        let persistentStore = try persistentStore(for: objectID)
        let container = try cloudKitContainer()
        let existingShare = try persistentContainer.fetchShares(matching: [objectID])[objectID]

        if let existingShare, existingShare.currentUserParticipant?.role != .owner {
            // A participant can open the sharing screen, but only the owner may change the share itself.
            guard existingShare.url != nil else {
                throw CloudKitCollectionSharingError.shareURLUnavailable
            }
            return (share: existingShare, container: container)
        }

        let collectionShare: CKShare
        if let existingShare {
            collectionShare = existingShare
        } else {
            try await prepareForSharing(objectID)
            collectionShare = try await makeShare(for: objectID)
        }

        let shareType = try await collectionShareType(for: collectionID)
        let readyShare = try await shareWithUpdatedMetadata(
            collectionShare,
            title: title,
            thumbnailImageData: shareThumbnailImageData(),
            shareType: shareType,
            in: persistentStore
        )
        return (share: readyShare, container: container)
    }

    func persistUpdatedShare(_ share: CKShare, for collectionID: UUID) async throws {
        let objectID = try await collectionObjectID(for: collectionID)
        let persistentStore = try persistentStore(for: objectID)
        _ = try await persistUpdatedShare(share, in: persistentStore)
    }

    func purgeSharedCollection(for collectionID: UUID) async throws {
        let objectID = try await collectionObjectID(for: collectionID)
        let persistentStore = try persistentStore(for: objectID)

        guard let share = try persistentContainer.fetchShares(matching: [objectID])[objectID] else {
            throw CloudKitCollectionSharingError.shareNotFound
        }

        // A share made by Core Data lives in a zone of its own. The default zone holds the user's
        // private data and must never be purged.
        let zoneID = share.recordID.zoneID
        guard zoneID.zoneName != Self.defaultZoneName else {
            throw CloudKitCollectionSharingError.shareNotFound
        }

        try await purgeZone(zoneID, in: persistentStore)
    }

    func sharingState(
        for collectionID: UUID
    ) async throws -> CollectionSharingState {
        let objectID = try await collectionObjectID(for: collectionID)

        guard let share = try persistentContainer.fetchShares(matching: [objectID])[objectID] else {
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
    /// The zone Core Data keeps the user's unshared records in.
    static let defaultZoneName = "com.apple.coredata.cloudkit.zone"

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

    /// The share type marker for the collection, so sibling Foliora apps can tell whose invitation it is.
    func collectionShareType(for collectionID: UUID) async throws -> String? {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", collectionID as NSUUID)

            guard let collection = try self.context.fetch(request).first else {
                throw CloudKitCollectionSharingError.collectionNotFound(collectionID)
            }

            let kind = (collection.value(forKey: "kind") as? String).flatMap { CollectionKind(rawValue: $0) }
            return kind.map { CollectionShareType.value(for: $0) }
        }
    }

    func cloudKitContainer() throws -> CKContainer {
        guard let containerIdentifier = FolioraCoreDataStack.cloudKitContainerIdentifier(from: persistentContainer) else {
            throw CloudKitCollectionSharingError.containerUnavailable
        }

        return CKContainer(identifier: containerIdentifier)
    }

    func makeShare(for objectID: NSManagedObjectID) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let collection = try self.context.existingObject(with: objectID)
                    self.persistentContainer.share([collection], to: nil) { _, share, _, error in
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
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Detaches the collection from its home before sharing.
    ///
    /// Sharing takes the whole object graph, so a collection still linked to its home would drag
    /// the home and its other collections into the share. New collections keep only a snapshot of
    /// the home; this covers collections saved before that.
    func prepareForSharing(_ objectID: NSManagedObjectID) async throws {
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

    /// Brings the share's title, thumbnail and type up to date and returns the share as stored.
    ///
    /// The stored share is the one to hand to the sharing screen: saving gives it the server's
    /// current version, and a stale one fails to save again.
    func shareWithUpdatedMetadata(
        _ share: CKShare,
        title: String,
        thumbnailImageData: Data?,
        shareType: String?,
        in persistentStore: NSPersistentStore
    ) async throws -> CKShare {
        var needsPersisting = share.url == nil

        if needsTitleUpdate(share, title: title) {
            share[CKShare.SystemFieldKey.title] = title
            needsPersisting = true
        }

        if let thumbnailImageData, needsThumbnailUpdate(share, thumbnailImageData: thumbnailImageData) {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailImageData
            needsPersisting = true
        }

        if let shareType, (share[CKShare.SystemFieldKey.shareType] as? String) != shareType {
            share[CKShare.SystemFieldKey.shareType] = shareType
            needsPersisting = true
        }

        let currentShare: CKShare
        if needsPersisting {
            currentShare = try await persistUpdatedShare(share, in: persistentStore)
        } else {
            currentShare = share
        }

        guard currentShare.url != nil else {
            throw CloudKitCollectionSharingError.shareURLUnavailable
        }

        return currentShare
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

    func purgeZone(_ zoneID: CKRecordZone.ID, in persistentStore: NSPersistentStore) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            persistentContainer.purgeObjectsAndRecordsInZone(with: zoneID, in: persistentStore) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func persistentStore(for objectID: NSManagedObjectID) throws -> NSPersistentStore {
        guard let persistentStore = objectID.persistentStore else {
            throw CloudKitCollectionSharingError.persistentStoreNotFound
        }

        return persistentStore
    }
}

/// Defines the supported cloud kit collection sharing error values.
enum CloudKitCollectionSharingError: LocalizedError {
    case collectionNotFound(UUID)
    case persistentStoreNotFound
    case containerUnavailable
    case shareNotCreated
    case shareNotFound
    /// The share has no link yet, because the collection has not reached iCloud.
    case shareURLUnavailable

    var errorDescription: String? {
        switch self {
        case .collectionNotFound(let collectionID):
            return "No CollectionEntity found for \(collectionID)."
        case .persistentStoreNotFound:
            return "No persistent store found for the shared collection."
        case .containerUnavailable:
            return "CloudKit container of the Core Data store is unavailable."
        case .shareNotCreated:
            return "Core Data did not return a CloudKit share."
        case .shareNotFound:
            return "The collection has no CloudKit share to remove."
        case .shareURLUnavailable:
            return String(localized: "collection.sharing.error.not_uploaded")
        }
    }
}
