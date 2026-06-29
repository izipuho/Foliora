import CloudKit
import CoreData
import Foundation
import OSLog

private let sharingTraceLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Catalog",
    category: "CloudSharing"
)

private func sharingTrace(_ message: String) {
    sharingTraceLogger.debug("SHARING_TRACE \(message, privacy: .public)")
}

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
        let startedAt = CFAbsoluteTimeGetCurrent()
        sharingTrace("fetchShare begin collectionID=\(collectionID)")
        do {
            let collection = try await collectionEntity(for: collectionID)
            let share = try persistentContainer.fetchShares(matching: [collection.objectID])[collection.objectID]
            sharingTrace(
                "fetchShare end result=\(share == nil ? "notFound" : "found") durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) hasURL=\(share?.url != nil) collectionID=\(collectionID)"
            )
            return share
        } catch {
            sharingTrace(
                "fetchShare end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) error=\(String(describing: error)) collectionID=\(collectionID)"
            )
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
    ) async throws -> CKShare {
        let startedAt = CFAbsoluteTimeGetCurrent()
        sharingTrace("createShare begin collectionID=\(collectionID)")
        do {
            let collection = try await collectionEntity(for: collectionID)
            let persistentStore = try persistentStore(for: collection)

            let searchStartedAt = CFAbsoluteTimeGetCurrent()
            sharingTrace("existingShare search begin collectionID=\(collectionID)")
            let sharesBefore: [NSManagedObjectID: CKShare]
            do {
                sharesBefore = try persistentContainer.fetchShares(matching: [collection.objectID])
            } catch {
                sharingTrace(
                    "existingShare search end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - searchStartedAt) * 1000) error=\(String(describing: error)) collectionID=\(collectionID)"
                )
                throw error
            }
            let existingShare = sharesBefore[collection.objectID]
            sharingTrace(
                "existingShare search end result=\(existingShare == nil ? "notFound" : "found") durationMs=\((CFAbsoluteTimeGetCurrent() - searchStartedAt) * 1000) hasURL=\(existingShare?.url != nil) collectionID=\(collectionID)"
            )

            if let existingShare {
                let share: CKShare
                if existingShare.url != nil {
                    share = existingShare
                } else {
                    share = try await savedShare(
                        existingShare,
                        title: nil,
                        branch: "existingShare",
                        objectID: collection.objectID,
                        in: persistentStore
                    )
                }
                sharingTrace(
                    "createShare end result=success existingShare=found durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) hasURL=\(share.url != nil) collectionID=\(collectionID)"
                )
                return share
            }

            try await prepareForSharing(collection)
            let share = try await share(collection)

            let savedShare = try await savedShare(
                share,
                title: title,
                branch: "newShare",
                objectID: collection.objectID,
                in: persistentStore
            )
            sharingTrace(
                "createShare end result=success existingShare=notFound durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) hasURL=\(savedShare.url != nil) collectionID=\(collectionID)"
            )
            return savedShare
        } catch {
            sharingTrace(
                "createShare end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) error=\(String(describing: error)) collectionID=\(collectionID)"
            )
            throw error
        }
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        sharingTrace("persistentContainer.share begin objectID=\(collection.objectID.uriRepresentation().absoluteString)")
        do {
            let share: CKShare = try await withCheckedThrowingContinuation { continuation in
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
            sharingTrace(
                "persistentContainer.share end result=success durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) hasURL=\(share.url != nil) objectID=\(collection.objectID.uriRepresentation().absoluteString)"
            )
            return share
        } catch {
            sharingTrace(
                "persistentContainer.share end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) error=\(String(describing: error)) objectID=\(collection.objectID.uriRepresentation().absoluteString)"
            )
            throw error
        }
    }

    func prepareForSharing(_ collection: NSManagedObject) async throws {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let objectID = collection.objectID
        sharingTrace("prepareForSharing begin objectID=\(objectID.uriRepresentation().absoluteString)")

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
            sharingTrace(
                "prepareForSharing end result=success durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) objectID=\(objectID.uriRepresentation().absoluteString)"
            )
        } catch {
            sharingTrace(
                "prepareForSharing end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) error=\(String(describing: error)) objectID=\(objectID.uriRepresentation().absoluteString)"
            )
            throw error
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

    func normalizedShareTitle(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func needsTitleUpdate(_ share: CKShare, title: String) -> Bool {
        let newTitle = normalizedShareTitle(title)
        guard !newTitle.isEmpty else { return false }

        let currentTitle = normalizedShareTitle(share[CKShare.SystemFieldKey.title] as? String)
        return currentTitle != newTitle
    }

    func savedShare(
        _ share: CKShare,
        title: String? = nil,
        branch: String,
        objectID: NSManagedObjectID,
        in persistentStore: NSPersistentStore
    ) async throws -> CKShare {
        var needsPersisting = share.url == nil
        var persistReasons: [String] = []
        if share.url == nil {
            persistReasons.append("missingURL")
        }
        let initialURLStartedAt = CFAbsoluteTimeGetCurrent()
        sharingTrace(
            "shareURL check begin objectID=\(objectID.uriRepresentation().absoluteString)"
        )
        sharingTrace(
            "shareURL check end result=success durationMs=\((CFAbsoluteTimeGetCurrent() - initialURLStartedAt) * 1000) hasURL=\(share.url != nil) objectID=\(objectID.uriRepresentation().absoluteString)"
        )

        if let title, needsTitleUpdate(share, title: title) {
            persistReasons.append("titleChanged")
            share[CKShare.SystemFieldKey.title] = title
            needsPersisting = true
        }

        if needsPersisting {
            sharingTrace(
                "persist decision branch=\(branch) hasURL=\(share.url != nil) needsPersisting=\(needsPersisting) reasons=[\(persistReasons.joined(separator: ","))]"
            )
            _ = try await persistUpdatedShare(share, in: persistentStore)

            let refetchStartedAt = CFAbsoluteTimeGetCurrent()
            sharingTrace("postPersist fetchShare begin objectID=\(objectID.uriRepresentation().absoluteString)")
            let sharesAfterPersist: [NSManagedObjectID: CKShare]
            do {
                sharesAfterPersist = try persistentContainer.fetchShares(matching: [objectID])
            } catch {
                sharingTrace(
                    "postPersist fetchShare end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - refetchStartedAt) * 1000) error=\(String(describing: error)) objectID=\(objectID.uriRepresentation().absoluteString)"
                )
                throw error
            }
            let refetchedShare = sharesAfterPersist[objectID]
            sharingTrace(
                "postPersist fetchShare end result=\(refetchedShare == nil ? "notFound" : "found") durationMs=\((CFAbsoluteTimeGetCurrent() - refetchStartedAt) * 1000) hasURL=\(refetchedShare?.url != nil) objectID=\(objectID.uriRepresentation().absoluteString)"
            )

            guard let refetchedShare else {
                throw CloudKitCollectionSharingError.shareNotCreated
            }

            let postPersistURLStartedAt = CFAbsoluteTimeGetCurrent()
            sharingTrace("postPersist shareURL begin objectID=\(objectID.uriRepresentation().absoluteString)")
            guard refetchedShare.url != nil else {
                sharingTrace(
                    "postPersist shareURL end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - postPersistURLStartedAt) * 1000) hasURL=false objectID=\(objectID.uriRepresentation().absoluteString)"
                )
                throw CloudKitCollectionSharingError.shareURLUnavailable
            }
            sharingTrace(
                "postPersist shareURL end result=success durationMs=\((CFAbsoluteTimeGetCurrent() - postPersistURLStartedAt) * 1000) hasURL=true objectID=\(objectID.uriRepresentation().absoluteString)"
            )

            return refetchedShare
        }

        let savedShareURLStartedAt = CFAbsoluteTimeGetCurrent()
        sharingTrace("savedShare shareURL begin objectID=\(objectID.uriRepresentation().absoluteString)")
        guard share.url != nil else {
            sharingTrace(
                "savedShare shareURL end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - savedShareURLStartedAt) * 1000) hasURL=false objectID=\(objectID.uriRepresentation().absoluteString)"
            )
            throw CloudKitCollectionSharingError.shareURLUnavailable
        }
        sharingTrace(
            "savedShare shareURL end result=success durationMs=\((CFAbsoluteTimeGetCurrent() - savedShareURLStartedAt) * 1000) hasURL=true objectID=\(objectID.uriRepresentation().absoluteString)"
        )

        return share
    }

    func persistUpdatedShare(_ share: CKShare, in persistentStore: NSPersistentStore) async throws -> CKShare {
        let startedAt = CFAbsoluteTimeGetCurrent()
        sharingTrace("persistUpdatedShare begin hasURL=\(share.url != nil)")
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
            sharingTrace(
                "persistUpdatedShare end result=success durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) hasURL=\(persistedShare.url != nil)"
            )
            return persistedShare
        } catch {
            sharingTrace(
                "persistUpdatedShare end result=error durationMs=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1000) error=\(String(describing: error))"
            )
            throw error
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
