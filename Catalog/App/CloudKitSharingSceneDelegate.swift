import UIKit
import CloudKit
import CoreData
import os

final class CloudKitSharingSceneDelegate: UIResponder, UIWindowSceneDelegate {
    private let logger = Logger(subsystem: "com.izipuho.FolioraBells", category: "CloudKitSharing")

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        logger.info("received share metadata")
        FolioraCloudKitShareInvitationAcceptor.accept(cloudKitShareMetadata, logger: logger)
    }
}

enum FolioraCloudKitShareInvitationAcceptor {
    static func accept(_ metadata: CKShare.Metadata, logger: Logger) {
        guard let container = FolioraAppDelegate.coreDataContainer else {
            logger.error("accept failed: Core Data container is not available")
            return
        }

        guard let sharedStore = sharedPersistentStore(in: container) else {
            logger.error("accept failed: shared persistent store is not available")
            return
        }

        logger.info("accept started")
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                logger.error("accept failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            logger.info("accept succeeded")
        }
    }

    private static func sharedPersistentStore(in container: NSPersistentCloudKitContainer) -> NSPersistentStore? {
        let sharedStoreURL = container.persistentStoreDescriptions.first {
            $0.cloudKitContainerOptions?.databaseScope == .shared
        }?.url

        return container.persistentStoreCoordinator.persistentStores.first {
            $0.url == sharedStoreURL
        }
    }
}
