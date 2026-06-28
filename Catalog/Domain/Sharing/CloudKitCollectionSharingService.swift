import CloudKit
import CoreData
import Foundation

protocol CollectionSharingService: Sendable {
    func fetchShare(for collectionID: UUID) async throws -> CKShare?

    func localSharingReadiness(for collectionID: UUID) async throws -> (isReady: Bool, reasons: [String])

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

        try await prepareForSharing(collection)
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
        let hasExternalParticipants = participants.contains {
            !$0.isCurrentUser && $0.role != .owner && $0.acceptanceStatus != .removed
        }

        return CollectionSharingState(
            isShared: hasExternalParticipants,
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

    func prepareForSharing(_ collection: NSManagedObject) async throws {
        let objectID = collection.objectID

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

    func syncCollectionLocations(for collection: NSManagedObject) {
        guard let homeID = collection.value(forKey: "homeID") as? UUID else { return }

        let locations = fetchLocations(in: homeID)
        let existingLocations = relatedObjects(collection, "collectionLocations")
        var existingBySourceID: [UUID: NSManagedObject] = [:]
        for entity in existingLocations {
            guard let sourceLocationID = entity.value(forKey: "sourceLocationID") as? UUID else { continue }
            existingBySourceID[sourceLocationID] = existingBySourceID[sourceLocationID] ?? entity
        }

        var syncedBySourceID: [UUID: NSManagedObject] = [:]
        let sourceIDs = Set(locations.map { uuidValue($0, "id") })

        for (sortOrder, location) in locations.enumerated() {
            let sourceLocationID = uuidValue(location, "id")
            let entity = existingBySourceID[sourceLocationID] ?? NSEntityDescription.insertNewObject(
                forEntityName: "CollectionLocationEntity",
                into: context
            )
            entity.setValue(sourceLocationID, forKey: "id")
            entity.setValue(sourceLocationID, forKey: "sourceLocationID")
            entity.setValue(location.value(forKey: "kindRaw"), forKey: "kindRaw")
            entity.setValue(location.value(forKey: "name"), forKey: "name")
            entity.setValue(location.value(forKey: "notes"), forKey: "notes")
            entity.setValue(sortOrder, forKey: "sortOrder")
            entity.setValue(false, forKey: "isArchived")
            entity.setValue(collection, forKey: "collection")
            syncedBySourceID[sourceLocationID] = entity
        }

        for location in locations {
            let sourceLocationID = uuidValue(location, "id")
            guard let entity = syncedBySourceID[sourceLocationID] else { continue }
            let parent = (location.value(forKey: "parent") as? NSManagedObject)
                .map { uuidValue($0, "id") }
                .flatMap { syncedBySourceID[$0] }
            entity.setValue(parent, forKey: "parent")
        }

        for entity in existingLocations {
            guard
                let sourceLocationID = entity.value(forKey: "sourceLocationID") as? UUID,
                !sourceIDs.contains(sourceLocationID)
            else {
                continue
            }

            if relatedObjects(entity, "bells").isEmpty {
                context.delete(entity)
            } else {
                entity.setValue(true, forKey: "isArchived")
                entity.setValue(nil, forKey: "parent")
            }
        }

        backfillBellCollectionLocations(in: collection)
    }

    func fetchLocations(in homeID: UUID) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "LocationEntity")
        request.predicate = NSPredicate(format: "home.id == %@", homeID as NSUUID)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func backfillBellCollectionLocations(in collection: NSManagedObject) {
        for bell in relatedObjects(collection, "bells") {
            guard bell.value(forKey: "collectionLocation") == nil else { continue }
            guard let location = bell.value(forKey: "location") as? NSManagedObject else { continue }
            let sourceLocationID = uuidValue(location, "id")
            let collectionLocation = relatedObjects(collection, "collectionLocations").first {
                ($0.value(forKey: "sourceLocationID") as? UUID) == sourceLocationID
            }
            bell.setValue(collectionLocation, forKey: "collectionLocation")
        }
    }

    func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
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
            return "Коллекция еще не загружена в iCloud. Попробуйте немного позже."
        }
    }
}
