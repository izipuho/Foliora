import UIKit
import CloudKit
import Combine
import CoreData

/// Defines the supported cloud kit share invitation acceptance state values.
enum CloudKitShareInvitationAcceptanceState: Equatable {
    case idle
    case accepting
    /// The invitation is accepted and the shared collection is on this device.
    case accepted
    /// The invitation is accepted, but the shared collection has not arrived from iCloud yet.
    case acceptedAwaitingSync
    case failed(message: String)
}

/// Provides cloud kit share invitation acceptance controller operations.
@MainActor
final class CloudKitShareInvitationAcceptanceController: ObservableObject {
    static let shared = CloudKitShareInvitationAcceptanceController()

    @Published private(set) var state: CloudKitShareInvitationAcceptanceState = .idle

    private init() {}

    func beginAccepting() {
        state = .accepting
    }

    func markAccepted() {
        state = .accepted
    }

    func markAcceptedAwaitingSync() {
        state = .acceptedAwaitingSync
    }

    func markFailed(message: String) {
        state = .failed(message: message)
    }

    func reset() {
        state = .idle
    }
}

/// Coordinates cloud kit sharing scene delegate behavior.
final class CloudKitSharingSceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// Receives the invitation that launched the app.
    ///
    /// When the app is not running, the system delivers the invitation here instead of calling
    /// `windowScene(_:userDidAcceptCloudKitShareWith:)`.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata else { return }
        FolioraCloudKitShareInvitationAcceptor.accept(cloudKitShareMetadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        FolioraCloudKitShareInvitationAcceptor.accept(cloudKitShareMetadata)
    }
}

/// Groups foliora cloud kit share invitation acceptor values and behavior.
@MainActor
enum FolioraCloudKitShareInvitationAcceptor {
    /// Invitations received before the Core Data stack was ready, e.g. the one that launched the app.
    private static var invitationsAwaitingContainer: [CKShare.Metadata] = []

    /// How many times the store is checked for the accepted collection, half a second apart.
    private static let importCheckCount = 60

    static func accept(_ metadata: CKShare.Metadata) {
        CloudKitShareInvitationAcceptanceController.shared.beginAccepting()

        guard let container = FolioraAppDelegate.coreDataContainer else {
            invitationsAwaitingContainer.append(metadata)
            return
        }

        accept(metadata, into: container)
    }

    /// Accepts the invitations that arrived while the Core Data stack was still loading.
    static func persistentContainerDidBecomeAvailable() {
        guard let container = FolioraAppDelegate.coreDataContainer else { return }

        let invitations = invitationsAwaitingContainer
        invitationsAwaitingContainer = []
        for metadata in invitations {
            accept(metadata, into: container)
        }
    }

    private static func accept(_ metadata: CKShare.Metadata, into container: NSPersistentCloudKitContainer) {
        guard let sharedStore = FolioraCoreDataStack.sharedPersistentStore(in: container) else {
            CloudKitShareInvitationAcceptanceController.shared.markFailed(
                message: String(localized: "collection.sharing.error.shared_store_unavailable")
            )
            return
        }

        // Opening an invitation that is already accepted brings no new collection, so there is nothing to wait for.
        let knownShares = (try? container.fetchShares(in: sharedStore)) ?? []
        let isAlreadyAccepted = knownShares.contains { $0.recordID == metadata.share.recordID }
        let collectionCountBeforeAccepting = sharedCollectionCount(in: container)

        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            Task { @MainActor in
                if let error {
                    CloudKitShareInvitationAcceptanceController.shared.markFailed(
                        message: userFacingMessage(for: error)
                    )
                    return
                }

                if isAlreadyAccepted {
                    CloudKitShareInvitationAcceptanceController.shared.markAccepted()
                    return
                }

                let didArrive = await waitForSharedCollection(
                    in: container,
                    countBeforeAccepting: collectionCountBeforeAccepting
                )
                if didArrive {
                    CloudKitShareInvitationAcceptanceController.shared.markAccepted()
                } else {
                    CloudKitShareInvitationAcceptanceController.shared.markAcceptedAwaitingSync()
                }
            }
        }
    }

    /// Waits until the accepted collection arrives from iCloud, or gives up after a while.
    ///
    /// Accepting an invitation only grants access; the records are imported afterwards.
    private static func waitForSharedCollection(
        in container: NSPersistentCloudKitContainer,
        countBeforeAccepting: Int
    ) async -> Bool {
        for _ in 0..<importCheckCount {
            if sharedCollectionCount(in: container) > countBeforeAccepting {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        return sharedCollectionCount(in: container) > countBeforeAccepting
    }

    private static func sharedCollectionCount(in container: NSPersistentCloudKitContainer) -> Int {
        guard let sharedStore = FolioraCoreDataStack.sharedPersistentStore(in: container) else { return 0 }

        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
        request.affectedStores = [sharedStore]
        return (try? container.viewContext.count(for: request)) ?? 0
    }

    private static func userFacingMessage(for error: Error) -> String {
        let message = String(localized: "collection.sharing.error.accept_failed")
        #if DEBUG
        return "\(message)\n\(error.localizedDescription)\n\(String(reflecting: error))"
        #else
        return message
        #endif
    }
}
