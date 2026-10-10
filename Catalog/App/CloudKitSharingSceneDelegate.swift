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

/// A share invitation handed over by a sibling Foliora app, waiting for the user's confirmation.
///
/// The system asks the user before delivering an invitation to an app. A link from another app
/// carries no such consent, so the app asks itself.
struct PendingShareInvitation {
    let title: String?
    let metadata: CKShare.Metadata
}

/// Provides cloud kit share invitation acceptance controller operations.
@MainActor
final class CloudKitShareInvitationAcceptanceController: ObservableObject {
    static let shared = CloudKitShareInvitationAcceptanceController()

    @Published private(set) var state: CloudKitShareInvitationAcceptanceState = .idle
    @Published private(set) var invitationAwaitingConfirmation: PendingShareInvitation?

    private init() {}

    func requestConfirmation(for metadata: CKShare.Metadata) {
        state = .idle
        invitationAwaitingConfirmation = PendingShareInvitation(
            title: metadata.share[CKShare.SystemFieldKey.title] as? String,
            metadata: metadata
        )
    }

    func clearConfirmation() {
        invitationAwaitingConfirmation = nil
    }

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
        if let kind = CollectionShareType.kind(of: metadata.share), kind != CollectionAppLink.currentAppKind {
            handOff(metadata, to: kind)
            return
        }

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

    /// Handles a share invitation link handed over by a sibling Foliora app.
    ///
    /// Returns `false` when the URL is not such a link. The invitation is accepted only after
    /// the user confirms it.
    static func handleInvitationLink(_ url: URL) -> Bool {
        guard let shareURL = CollectionAppLink.shareURL(
            fromInvitationLink: url,
            for: CollectionAppLink.currentAppKind
        ) else {
            return false
        }

        CloudKitShareInvitationAcceptanceController.shared.beginAccepting()
        Task { @MainActor in
            do {
                let metadata = try await shareMetadata(for: shareURL)
                CloudKitShareInvitationAcceptanceController.shared.requestConfirmation(for: metadata)
            } catch {
                CloudKitShareInvitationAcceptanceController.shared.markFailed(
                    message: userFacingMessage(for: error)
                )
            }
        }
        return true
    }

    /// Accepts an invitation the user confirmed.
    static func acceptConfirmed(_ invitation: PendingShareInvitation) {
        CloudKitShareInvitationAcceptanceController.shared.clearConfirmation()
        accept(invitation.metadata)
    }

    static func declinePendingInvitation() {
        CloudKitShareInvitationAcceptanceController.shared.clearConfirmation()
    }

    /// Passes an invitation meant for a sibling app on to that app instead of accepting it here.
    private static func handOff(_ metadata: CKShare.Metadata, to kind: CollectionKind) {
        let failureMessage = String.localizedStringWithFormat(
            String(localized: "collection.sharing.error.other_app_required"),
            CollectionAppLink.appName(for: kind)
        )

        guard let shareURL = metadata.share.url,
              let link = CollectionAppLink.shareInvitationURL(for: kind, shareURL: shareURL)
        else {
            CloudKitShareInvitationAcceptanceController.shared.markFailed(message: failureMessage)
            return
        }

        Task { @MainActor in
            let didOpen = await UIApplication.shared.open(link)
            if didOpen {
                CloudKitShareInvitationAcceptanceController.shared.reset()
            } else {
                CloudKitShareInvitationAcceptanceController.shared.markFailed(message: failureMessage)
            }
        }
    }

    nonisolated private static func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            CKContainer.default().fetchShareMetadata(with: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: error ?? ShareInvitationLinkError.metadataUnavailable)
                }
            }
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

private enum ShareInvitationLinkError: Error {
    case metadataUnavailable
}
